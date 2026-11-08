'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const sharp=require('sharp');
const scene=require('../scene_description');
const trial=require('../scene_trial');
const id=n=>n.toString(16).padStart(32,'0');
const env={SCENE_TRIAL_ID:'room-test',SCENE_TRIAL_UID:'uid',SCENE_TRIAL_MAX_REQUESTS:'50',SCENE_TRIAL_BUDGET_MICRO_USD:'10000',QWEN_INPUT_USD_PER_MILLION:'0.2',QWEN_OUTPUT_USD_PER_MILLION:'1.6'};
const observation={category:'table',position:'left',detail:'木枱'};
const usage={prompt_tokens:367,completion_tokens:61,total_tokens:428};
const reply={status:'complete',metrics:{usage,estimate:scene.estimate(usage,{input:0.2,output:1.6})}};
async function data(mode='update') {
  const bytes=await sharp({create:{width:8,height:4,channels:3,background:'white'}}).jpeg().toBuffer();
  return {schemaVersion:2,requestId:id(30),expectedUid:'uid',mode,mimeType:'image/jpeg',jpegBase64:bytes.toString('base64')};
}
function response(sentences,observations=[observation]) {
  return new Response(JSON.stringify({choices:[{finish_reason:'stop',message:{content:JSON.stringify({sentences,observations})}}],usage}),{headers:{'content-type':'application/json'}});
}
function database(state) {
  const docs=new Map([['users/uid',{status:'active'}],['scene_description_trials/room-test',state]]);
  let serial=Promise.resolve();
  return {docs,doc:p=>p,runTransaction(fn){const op=serial.then(async()=>{
    const writes=[];
    const value=await fn({get:async p=>({exists:docs.has(p),data:()=>docs.get(p)}),set:(p,v,o)=>writes.push([p,v,o])});
    for(const [p,v,o] of writes)docs.set(p,o?.merge?{...docs.get(p),...v}:v);
    return value;
  });serial=op.catch(()=>{});return op;}};
}
function stopped(config,now=1000) {
  return {fingerprint:config.fingerprint,count:7,spentMicroUsd:3483,ids:Array.from({length:7},(_,i)=>id(i)),inFlight:null,halted:true,lastStatus:'complete',
    recovery:{status:'consumed'},window:{id:'bounded-mode-test',status:'ready',baseCount:7,maxCount:10,expiresAtMs:now+60000}};
}
test('v2 selects server-owned overview/update contracts and sends only the current photograph',async()=>{
  for(const mode of ['overview','update']) {
    let calls=0;
    const sentences=mode==='overview'?['左邊有木枱。','右邊見到門。']:['左邊見到木枱。'];
    const result=await scene.describe(await data(mode),{key:'fake',rates:{input:0.2,output:1.6},fetcher:async(_,options)=>{
      calls++;
      const body=JSON.parse(options.body);
      assert.deepEqual(body.response_format,{type:'json_object'});
      assert.equal(body.messages.length,2);
      assert.equal(body.messages[1].content.filter(c=>c.type==='image_url').length,1);
      assert.match(body.messages[0].content,mode==='update'?/只寫一句/:/寫兩至三句/);
      return response(sentences);
    }});
    assert.equal(calls,1);
    assert.equal(result.mode,mode);
    assert.equal(result.text,sentences.join(''));
    assert.deepEqual(result.observations,[observation]);
    assert.deepEqual(result.metrics.usage,usage);
  }
});
test('v2 refuses unsafe facts, extra fields, wrong sentence count and malformed modes without repair calls',async()=>{
  for(const [sentences,observations] of [
    [['枱。','門。'],[observation]],
    [['左邊有枱。'],[{...observation,detail:'可以安全通行'}]],
    [['左邊有枱。'],[{...observation,category:'url'}]],
    [['左邊有枱。'],[observation,observation]],
    [['左邊有枱。'],[{...observation,extra:'private'}]],
  ]) {
    let calls=0;
    const result=await scene.describe(await data(),{key:'fake',fetcher:async()=>{calls++;return response(sentences,observations);}});
    assert.equal(calls,1);assert.equal(result.status,'rejected');
    assert.ok(!('text' in result));assert.ok(!('observations' in result));
    assert.deepEqual(result.metrics.usage,usage);
  }
  await assert.rejects(scene.describe({...await data(),mode:'caller-prompt'},{key:'fake',fetcher:()=>assert.fail('network')}),{code:'invalid-argument'});
});
test('bounded window keeps old count/cost/IDs, wins once concurrently, and stops at its ceiling',async()=>{
  const config=trial.configure(env),initial=stopped(config),db=database(initial);
  const attempts=await Promise.allSettled([scene.reserve(db,'uid',id(10),1000,config,3000),scene.reserve(db,'uid',id(11),1000,config,3000)]);
  assert.equal(attempts.filter(r=>r.status==='fulfilled').length,1);
  let ledger=db.docs.get('scene_description_trials/room-test');
  await trial.settle(db,config,ledger.inFlight,reply);
  for(let n=12;n<14;n++) {
    await scene.reserve(db,'uid',id(n),1000+(n-10)*3100,config,3000);
    await trial.settle(db,config,id(n),reply);
  }
  ledger=db.docs.get('scene_description_trials/room-test');
  assert.equal(ledger.count,10);assert.equal(ledger.spentMicroUsd,3483+3*171);
  assert.deepEqual(ledger.ids.slice(0,7),initial.ids);
  assert.equal(ledger.halted,true);assert.equal(ledger.window.status,'consumed');
  await assert.rejects(scene.reserve(db,'uid',id(20),20000,config,3000),{code:'resource-exhausted'});
});
test('window cannot bypass expiry, configuration ceiling, budget or unknown settlement',async()=>{
  const config=trial.configure(env);
  assert.equal(config.maxRequests,50);
  assert.throws(()=>trial.configure({...env,SCENE_TRIAL_MAX_REQUESTS:'51'}),{code:'failed-precondition'});
  for(const change of [
    {window:{...stopped(config).window,expiresAtMs:999}},
    {window:{...stopped(config).window,maxCount:51}},
    {spentMicroUsd:8000}, {lastStatus:'usage-unknown'},
  ]) assert.throws(()=>trial.allocate({...stopped(config),...change},id(30),config,1000),{code:'resource-exhausted'});
  const db=database(stopped(config));
  await scene.reserve(db,'uid',id(30),1000,config,3000);
  await trial.settle(db,config,id(30),null);
  const ledger=db.docs.get('scene_description_trials/room-test');
  assert.equal(ledger.window.status,'halted');assert.equal(ledger.spentMicroUsd,3483+2458);
  await assert.rejects(scene.reserve(db,'uid',id(31),5000,config,3000),{code:'resource-exhausted'});
});
test('pre-provider quota errors are explicitly identifiable without secrets or inference',async()=>{
  Object.assign(process.env,env,{SCENE_DESCRIPTION_ENABLED:'true'});
  const config=trial.configure(env),state=stopped(config);
  state.window.status='consumed';
  const callable=require('../scene_function').createSceneFunction(database(state),{});
  await assert.rejects(callable.run({app:{appId:'test'},auth:{uid:'uid',token:{firebase:{sign_in_provider:'google.com'}}},data:await data()}),e=>{
    assert.equal(e.code,'resource-exhausted');assert.deepEqual(e.details,{beforeProvider:true});return true;
  });
});
test('successful mode response returns numerical quota and never stores scene content',async()=>{
  const config=trial.configure(env),db=database(stopped(config,Date.now()));
  const request={app:{appId:'test'},auth:{uid:'uid',token:{firebase:{sign_in_provider:'google.com'}}},data:await data()};
  const result=await scene.handle(request,{db,enabled:true,trial:config,key:()=> 'fake',rates:{input:0.2,output:1.6},fetcher:async()=>response(['左邊見到木枱。'])});
  assert.equal(result.limits.count,8);assert.equal(result.limits.maxRequests,50);
  assert.equal(result.limits.windowRemaining,2);assert.equal(result.limits.spentMicroUsd,3483+171);
  assert.ok(!JSON.stringify([...db.docs.values()]).includes('木枱'));
  assert.ok(!JSON.stringify([...db.docs.values()]).includes('observations'));
});
test('post-provider settlement failure is never labelled safe to resend',async()=>{
  const config=trial.configure(env),db=database(stopped(config,Date.now()));
  const request={app:{appId:'test'},auth:{uid:'uid',token:{firebase:{sign_in_provider:'google.com'}}},data:await data()};
  let calls=0;
  await assert.rejects(scene.handle(request,{db,enabled:true,trial:config,key:()=> 'fake',rates:{input:0.2,output:1.6},fetcher:async()=>{
    calls++;db.docs.get('scene_description_trials/room-test').fingerprint='changed';
    return response(['左邊見到木枱。']);
  }}),error=>{assert.equal(error.code,'failed-precondition');assert.notEqual(error.beforeProvider,true);return true;});
  assert.equal(calls,1);assert.equal(db.docs.get('scene_description_trials/room-test').inFlight,id(30));
});
