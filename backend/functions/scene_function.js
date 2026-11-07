'use strict';
const {onCall,HttpsError}=require('firebase-functions/v2/https');
const {defineSecret}=require('firebase-functions/params');
// Explicitly disabled until account, region, data policy and paid-test allowance
// are configured. Reuses Firebase Auth/App Check and Secret Manager.
exports.createSceneFunction=(db,options)=>{
const scene = require('./scene_description');
const sceneTrial = require('./scene_trial');
const qwenKey = defineSecret('DASHSCOPE_API_KEY');
return onCall({...options,timeoutSeconds:40,secrets:[qwenKey]}, async request => {
  try {
    const rate = name => process.env[name]?.trim() ? Number(process.env[name]) : null;
    return await scene.handle(request,{db,enabled:process.env.SCENE_DESCRIPTION_ENABLED === 'true',
      trial:process.env.SCENE_DESCRIPTION_ENABLED === 'true'?sceneTrial.configure(process.env):null,
      key:()=>qwenKey.value(),base:process.env.QWEN_VL_BASE_URL,
      rates:{input:rate('QWEN_INPUT_USD_PER_MILLION'),output:rate('QWEN_OUTPUT_USD_PER_MILLION')}});
  } catch (error) {
    const code = error instanceof scene.SceneFailure || error instanceof sceneTrial.TrialFailure ? error.code : 'unavailable';
    throw new HttpsError(code,'場景描述未完成；沒有自動重試。取消後上游仍可能計費。');
  }
});

};
