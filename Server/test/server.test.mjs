import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer,configFromEnv} from '../server.mjs';
const token='a'.repeat(64);
const meal={title:'Eggs',items:[{id:'eggs',name:'Eggs',portion:'2 large',nutrition:{calories:144,protein:12.6,carbs:0.7,fat:9.6},confidence:'medium',assumptions:[]}],assumptions:[],questions:[]};
async function withServer(fn, extra={}) {
  let calls=0, lastInput;
  const server=createServer({accessToken:token,apiKey:'not-a-real-key',model:'test',...extra},async input=>{calls++;lastInput=input;return meal;});
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const base=`http://127.0.0.1:${server.address().port}`;
  const post=(value,headers={})=>fetch(base+'/v1/estimate',{method:'POST',headers:{'Authorization':`Bearer ${token}`,'Content-Type':'application/json',...headers},body:typeof value==='string'?value:JSON.stringify(value)});
  try { await fn({base,post,calls:()=>calls,lastInput:()=>lastInput}); }
  finally { server.closeAllConnections();await new Promise(r=>server.close(r)); }
}
test('server refuses missing/placeholder credentials',()=>{assert.throws(()=>configFromEnv({}));assert.throws(()=>configFromEnv({OPENAI_API_KEY:'replace-me',RECOMP_ACCESS_TOKEN:token}));assert.throws(()=>configFromEnv({OPENAI_API_KEY:'test',RECOMP_ACCESS_TOKEN:'short'}));});
test('safe local defaults',()=>{const c=configFromEnv({OPENAI_API_KEY:'test',RECOMP_ACCESS_TOKEN:token});assert.equal(c.host,'127.0.0.1');assert.equal(c.model,'gpt-4.1-mini');});
test('health route contains no secrets',()=>withServer(async({base})=>{const r=await fetch(base+'/health');assert.equal(r.status,200);assert.deepEqual(await r.json(),{ok:true});}));
test('wrong token fails before AI call',()=>withServer(async({post,calls})=>{const r=await post({description:'Eggs',images:[]},{Authorization:'Bearer wrong'});assert.equal(r.status,401);assert.equal(calls(),0);}));
test('valid text request reaches provider and returns review-only data',()=>withServer(async({post,calls,lastInput})=>{const r=await post({description:'Two eggs',images:[]});assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');assert.deepEqual(await r.json(),meal);assert.equal(calls(),1);assert.equal(lastInput().description,'Two eggs');}));
test('malformed JSON fails before provider',()=>withServer(async({post,calls})=>{const r=await post('{');assert.equal(r.status,400);assert.equal(calls(),0);}));
test('disallowed Health data fails before provider',()=>withServer(async({post,calls})=>{const r=await post({description:'Eggs',images:[],healthRecords:[]});assert.equal(r.status,400);assert.equal(calls(),0);}));
test('wrong content type fails',()=>withServer(async({post})=>{assert.equal((await post('{}',{'Content-Type':'text/plain'})).status,415);}));
test('compressed input rejected',()=>withServer(async({post})=>{assert.equal((await post('{}',{'Content-Encoding':'gzip'})).status,415);}));
test('oversized body rejected',()=>withServer(async({post,calls})=>{assert.equal((await post('x'.repeat(12_300_001))).status,413);assert.equal(calls(),0);}));
test('authenticated rate limit protects API spend',()=>withServer(async({post,calls})=>{assert.equal((await post({description:'Eggs',images:[]})).status,200);assert.equal((await post({description:'Eggs',images:[]})).status,429);assert.equal(calls(),1);},{perMinute:1}));
test('unknown route is not an open proxy',()=>withServer(async({base,calls})=>{const r=await fetch(base+'/https://elsewhere.invalid');assert.equal(r.status,404);assert.equal(calls(),0);}));
