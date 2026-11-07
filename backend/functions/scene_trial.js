'use strict';
const {createHash} = require('node:crypto');
// An immutable, operator-configured allowance; never reset at midnight/login.
// Micro-USD arithmetic avoids floating point overspend in the local estimate.
const INPUT_BOUND = 8192, OUTPUT_BOUND = 512;
class TrialFailure extends Error {
  constructor(code) { super(code); this.code=code; }
}
const fail=code=>{throw new TrialFailure(code);};
function configure(env) {
  const id=env.SCENE_TRIAL_ID, uid=env.SCENE_TRIAL_UID;
  const maxRequests=Number(env.SCENE_TRIAL_MAX_REQUESTS), budgetMicroUsd=Number(env.SCENE_TRIAL_BUDGET_MICRO_USD);
  if (!/^[a-z0-9-]{1,80}$/.test(id||'') || typeof uid!=='string' || !uid || uid.length>128 || uid.includes('/') ||
      !Number.isInteger(maxRequests) || maxRequests<1 || maxRequests>20 ||
      !Number.isInteger(budgetMicroUsd) || budgetMicroUsd<1 || budgetMicroUsd>10000 ||
      Number(env.QWEN_INPUT_USD_PER_MILLION)!==0.2 || Number(env.QWEN_OUTPUT_USD_PER_MILLION)!==1.6) fail('failed-precondition');
  const config={id,uid,maxRequests,budgetMicroUsd,reserveMicroUsd:Math.ceil((INPUT_BOUND*2+OUTPUT_BOUND*16)/10)};
  return {...config,fingerprint:createHash('sha256').update(JSON.stringify(config)).digest('hex')};
}
function allocate(old, requestId, config) {
  if (old && old.fingerprint!==config.fingerprint) fail('failed-precondition');
  const state=old||{fingerprint:config.fingerprint,count:0,spentMicroUsd:0,ids:[],inFlight:null,halted:false};
  if (!Number.isInteger(state.count) || state.count<0 || !Number.isInteger(state.spentMicroUsd) || state.spentMicroUsd<0 || !Array.isArray(state.ids) || state.ids.length!==state.count || new Set(state.ids).size!==state.ids.length) fail('failed-precondition');
  if (state.halted || state.inFlight || state.count>=config.maxRequests || state.ids.includes(requestId) ||
      state.spentMicroUsd+config.reserveMicroUsd>config.budgetMicroUsd) fail('resource-exhausted');
  return {...state,count:state.count+1,ids:[...state.ids,requestId],inFlight:requestId,
    reservedMicroUsd:config.reserveMicroUsd,maxRequests:config.maxRequests,budgetMicroUsd:config.budgetMicroUsd};
}
async function settle(db, config, requestId, result) {
  const ref=db.doc(`scene_description_trials/${config.id}`);
  await db.runTransaction(async tx=>{
    const old=(await tx.get(ref)).data();
    if (!old || old.fingerprint!==config.fingerprint || old.inFlight!==requestId) fail('failed-precondition');
    const usage=result?.metrics?.usage, estimate=result?.metrics?.estimate;
    const known=usage && ['prompt_tokens','completion_tokens','total_tokens'].every(k=>Number.isSafeInteger(usage[k])&&usage[k]>=0) && usage.total_tokens===usage.prompt_tokens+usage.completion_tokens && estimate && Number.isFinite(estimate.usd) && estimate.usd>=0 &&
      estimate.inputUsdPerMillion===0.2 && estimate.outputUsdPerMillion===1.6 &&
      usage.prompt_tokens<=INPUT_BOUND && usage.completion_tokens<=OUTPUT_BOUND;
    const charged=known?Math.ceil((usage.prompt_tokens*2+usage.completion_tokens*16)/10):config.reserveMicroUsd;
    tx.set(ref,{...old,inFlight:null,reservedMicroUsd:0,
      spentMicroUsd:old.spentMicroUsd+charged,halted:!known || charged>config.reserveMicroUsd,
      lastStatus:known?result.status:'usage-unknown',notBillingCap:true});
  });
}
module.exports={TrialFailure,configure,allocate,settle,INPUT_BOUND,OUTPUT_BOUND};
