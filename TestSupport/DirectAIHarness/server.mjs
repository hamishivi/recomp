// Synthetic loopback fixture. Never contacts OpenAI and never logs request bodies/keys.
import http from 'node:http';
import {writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
import {estimateSchema, instructions} from '../../Server/estimate.mjs';
const stats = {count:0, contracts:0, redirectHits:0};
const food = {title:'Synthetic egg',items:[{id:'egg',name:'Egg',portion:'1 large',nutrition:{calories:70,protein:6,carbs:0,fat:5},confidence:'low',assumptions:[],evidence:[]}],assumptions:[],questions:[]};
const envelope = value => ({status:'completed',output:[{type:'message',role:'assistant',status:'completed',content:[{type:'output_text',text:JSON.stringify(value)}]}]});
const server = http.createServer(async (req,res)=> {
  if(req.url==='/stats'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify(stats));return;}
  if(req.url==='/redirected'){stats.redirectHits++;res.end('{}');return;}
  const chunks=[];for await(const part of req)chunks.push(part);
  stats.count++;
  let input, context;
  try {
    input=JSON.parse(Buffer.concat(chunks).toString());
    assert.equal(req.method,'POST');
    assert.equal(req.headers.authorization,'Bearer sk-proj-SYNTHETIC-KEY-FOR-LOCAL-TESTS-ONLY');
    assert.equal(input.store,false); assert.equal(input.stream,false);
    assert.ok(input.max_output_tokens === 4500 || input.max_output_tokens === 12000);
    assert.ok(['gpt-5.6-terra','gpt-5.6-luna','gpt-5.6-sol','o3-mini','o1','gpt-4.1-mini','gpt-4.1'].includes(input.model));
    assert.equal(input.instructions,instructions);
    assert.deepEqual(input.text.format.schema,estimateSchema);
    assert.equal(input.text.format.strict,true);assert.equal(input.text.format.type,'json_schema');
    if (input.reasoning) { assert.ok(['none','low','medium','high'].includes(input.reasoning.effort)); }
    assert.ok(Object.keys(input).every(k => ['input','instructions','max_output_tokens','model','store','stream','text','reasoning'].includes(k)));
    assert.equal(input.input.length,1); assert.equal(input.input[0].role,'user');
    context=JSON.parse(input.input[0].content[0].text);
    assert.ok(Object.keys(context).every(k=>['description','clarification','currentEstimate','lockedItemIDs','excludedFoods','photoEvidence'].includes(k)));
    assert.equal(context.photoEvidence.length,input.input[0].content.length-1);
    for(let i=0;i<context.photoEvidence.length;i++) {
      assert.equal(context.photoEvidence[i].photoNumber,i+1);
      assert.equal(input.input[0].content[i+1].type,'input_image');
      assert.equal(input.input[0].content[i+1].detail,'high');
      assert.ok(input.input[0].content[i+1].image_url.startsWith('data:image/jpeg;base64,'));
    }
    stats.contracts++;
  } catch {res.writeHead(400,{'Content-Type':'application/json'});res.end(JSON.stringify({error:{message:'FIXTURE_CONTRACT_FAILURE'}}));return;}
  const mode=context.description;
  res.setHeader('Content-Type','application/json');
  if(mode.startsWith('status-')) {res.writeHead(Number(mode.split('-')[1]));res.end(JSON.stringify({error:{message:'SYNTHETIC_PRIVATE_VALUE_MUST_NOT_APPEAR'}}));return;}
  if(mode==='redirect'){res.writeHead(307,{Location:'/redirected'});res.end();return;}
  if(mode==='wrong-type'){res.setHeader('Content-Type','text/html');res.end(JSON.stringify(envelope(food)));return;}
  if(mode==='large'){res.setHeader('Content-Length',1_000_000);res.end('x'.repeat(1_000_000));return;}
  if(mode==='invalid-json'){res.end('not-json');return;}
  if(mode==='incomplete'){res.end(JSON.stringify({...envelope(food),status:'incomplete'}));return;}
  if(mode==='refusal'){res.end(JSON.stringify({status:'completed',output:[{type:'message',role:'assistant',status:'completed',content:[{type:'refusal',refusal:'PRIVATE_REFUSAL'}]}]}));return;}
  if(mode==='bad-photo'){const copy=structuredClone(food);copy.items[0].evidence=[{kind:'label',photoNumber:1,detail:'not actually supplied'}];res.end(JSON.stringify(envelope(copy)));return;}
  if(mode==='cancel'){setTimeout(()=>{if(!res.destroyed)res.end(JSON.stringify(envelope(food)));},400);return;}
  if(mode==='locks'){const copy=structuredClone(food);copy.items[0].nutrition.calories=999;res.end(JSON.stringify(envelope(copy)));return;}
  res.end(JSON.stringify(envelope(food)));
});
server.listen(0,'127.0.0.1',()=>writeFileSync(process.argv[2],String(server.address().port)));
