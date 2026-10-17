import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {createServer, configFromEnv} from '../server.mjs';
import {estimateMeal} from '../estimate.mjs';
const token = 'synthetic-access-token-'.repeat(3);
const input = {description:'Synthetic eggs',images:[],lockedItemIDs:[],excludedFoods:[],currentEstimate:null};
const meal = () => ({title:'Eggs',items:[{id:'eggs',name:'Eggs',portion:'2 eggs',nutrition:{calories:144,protein:12,carbs:1,fat:10},confidence:'medium',assumptions:[],evidence:[]}],assumptions:[],questions:[]});
const completed = value => ({status:'completed',output:[{type:'message',content:[{type:'output_text',text:JSON.stringify(value)}]}]});
async function serve(fn, provider=async()=>meal(), extra={}) {
  const server=createServer({accessToken:token,apiKey:'synthetic-private-secret',model:'test',perMinute:100,...extra},provider);
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`;
  const post=(body=input,headers={},signal)=>fetch(base+'/v1/estimate',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json',...headers},body:typeof body==='string'?body:JSON.stringify(body),signal});
  try { await fn({server,base,post}); } finally {server.closeAllConnections();await new Promise(resolve=>server.close(resolve));}
}
const tick = () => new Promise(resolve=>setTimeout(resolve,5));
async function until(check) { for(let i=0;i<200;i++){if(check())return;await tick();}throw new Error('Timed out waiting for deterministic test callback'); }

test('reject JSON-lookalike content types before charging for an estimate',()=>serve(async({post})=>{
  for(const content of ['application/jsonp','application/json-invalid']) assert.equal((await post(input,{'Content-Type':content})).status,415);
}));
test('accept normal JSON media type with charset',()=>serve(async({post})=>assert.equal((await post(input,{'Content-Type':'application/json; charset=UTF-8'})).status,200)));
test('configuration cannot reuse upstream API key as phone access token',()=>{
  const secret='sk-synthetic-key-not-valid-'.repeat(3);
  assert.throws(()=>configFromEnv({OPENAI_API_KEY:secret,RECOMP_ACCESS_TOKEN:secret}));
});
test('provider cannot cite a photo which was never supplied',async()=>{
  const output=meal();output.items[0].evidence=[{kind:'label',photoNumber:1,detail:'Invented photo reference'}];
  await assert.rejects(()=>estimateMeal(input,{apiKey:'test',model:'test'},async()=>new Response(JSON.stringify(completed(output)))),e=>e.status===502);
});
test('oversized streaming provider response is cancelled before buffering the full response',async()=>{
  let pulls=0,cancelled=false;
  const stream=new ReadableStream({pull(controller){pulls++;controller.enqueue(new Uint8Array(100_000).fill(32));if(pulls>=100)controller.close();},cancel(){cancelled=true;}});
  await assert.rejects(()=>estimateMeal(input,{apiKey:'test',model:'test'},async()=>new Response(stream)),e=>e.status===502);
  assert.ok(pulls<10,`buffered ${pulls} chunks`);assert.ok(cancelled);
});
test('two active requests cap concurrency and capacity recovers',async()=>{
  let active=0,calls=0;const releases=[];
  await serve(async({post})=>{
    const a=post();const b=post();await until(()=>active===2);
    const blocked=await post();assert.equal(blocked.status,429);assert.equal(calls,2);
    releases.splice(0).forEach(r=>r());assert.equal((await a).status,200);assert.equal((await b).status,200);
    const c=post();await until(()=>calls===3);releases.shift()();assert.equal((await c).status,200);
  },async()=>{active++;calls++;await new Promise(r=>releases.push(r));active--;return meal();});
});
test('client cancellation reaches upstream and releases concurrency slot',async()=>{
  let started=false,cancelled=false;
  await serve(async({post})=>{
    const abort=new AbortController();const pending=post(input,{},abort.signal).catch(e=>e);
    await until(()=>started);abort.abort();await pending;await until(()=>cancelled);
    assert.equal((await post()).status,200);
  },async(_input,_config,_fetch,signal)=>{
    if(started)return meal();started=true;
    await new Promise((resolve,reject)=>{signal.addEventListener('abort',()=>{cancelled=true;reject(new DOMException('Cancelled','AbortError'));},{once:true});});
    return meal();
  });
});
test('a failed provider releases slots and never leaks its error/secret',()=>serve(async({post})=>{
  for(let i=0;i<4;i++){const r=await post();assert.equal(r.status,502);assert.ok(!(await r.text()).includes('synthetic-private-secret'));}
},async()=>{throw new Error('synthetic-private-secret, private meal');}));
test('unauthenticated calls do not exhaust authorized daily quota',()=>serve(async({post})=>{
  for(let i=0;i<5;i++)assert.equal((await post(input,{Authorization:'Bearer invalid'})).status,401);
  assert.equal((await post()).status,200);assert.equal((await post()).status,429);
},undefined,{perDay:1}));
test('truncated socket upload never reaches provider or prevents subsequent requests',async()=>{
  let calls=0;
  await serve(async({base,post})=>{
    await new Promise(resolve=>{
      const req=http.request(base+'/v1/estimate',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','Content-Length':1000}});
      req.on('error',()=>{});req.on('close',resolve);req.write('{"description":');setTimeout(()=>req.destroy(),15);
    });
    await tick();assert.equal(calls,0);assert.equal((await post()).status,200);assert.equal(calls,1);
  },async()=>{calls++;return meal();});
});
test('oversized chunked request is rejected without a declared length',()=>serve(async({base})=>{
  const status=await new Promise((resolve,reject)=>{
    const req=http.request(base+'/v1/estimate',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json','Transfer-Encoding':'chunked'}},res=>{res.resume();resolve(res.statusCode);});
    req.on('error',reject);req.end(' '.repeat(12_300_001));
  });assert.equal(status,413);
}));
test('provider aborts are mapped to a retryable timeout without private messages',()=>serve(async({post})=>{
  const r=await post();assert.equal(r.status,504);assert.ok(!(await r.text()).includes('private timeout'));
},async()=>{throw new DOMException('private timeout','AbortError');}));
