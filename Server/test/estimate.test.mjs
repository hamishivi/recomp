import test from 'node:test';
import assert from 'node:assert/strict';
import {validateEstimate,validateRequest,jpegDimensions,buildProviderBody,decodeProviderResponse,enforceLocks,estimateMeal} from '../estimate.mjs';
const food = (id='rice') => ({id,name:'Cooked rice',portion:'1 cup cooked',nutrition:{calories:200,protein:4,carbs:44,fat:0.4},confidence:'low',assumptions:['Cooked weight not supplied.']});
const meal = () => ({title:'Lunch',items:[food()],assumptions:['Portion estimated.'],questions:['How much did you eat?']});
const request = () => ({description:'Rice',clarification:'',images:[],currentEstimate:null,lockedItemIDs:[],excludedFoods:[]});
// Minimal SOF header used only for validating our JPEG size/container guard.
const jpegHeader = Buffer.from([0xff,0xd8,0xff,0xc0,0,17,8,0,16,0,16,3,1,0x11,0,2,0x11,0,3,0x11,0,0xff,0xd9]);
const completed = value => ({status:'completed',output:[{type:'reasoning',summary:[]},{type:'message',content:[{type:'output_text',text:JSON.stringify(value)}]}]});
test('valid text-only request',()=>assert.equal(validateRequest(request()).description,'Rice'));
test('valid JPEG container',()=>{const r=request();r.images=[{base64:jpegHeader.toString('base64')}];assert.equal(validateRequest(r).images.length,1);assert.deepEqual(jpegDimensions(jpegHeader),{width:16,height:16});});
test('no-food response is allowed but not fabricated',()=>assert.deepEqual(validateEstimate({...meal(),items:[]}).items,[]));
test('reject extra Health or account fields',()=>assert.throws(()=>validateRequest({...request(),weight:85}),/Unexpected/));
test('reject empty request',()=>assert.throws(()=>validateRequest({...request(),description:''})));
test('reject more than six photos',()=>assert.throws(()=>validateRequest({...request(),images:Array(7).fill({base64:jpegHeader.toString('base64')})})));
test('reject external image URLs',()=>assert.throws(()=>validateRequest({...request(),images:[{url:'https://localhost/secrets'}]})));
test('reject malformed base64',()=>assert.throws(()=>validateRequest({...request(),images:[{base64:'#$='}]})));
test('reject non JPEG',()=>assert.throws(()=>validateRequest({...request(),images:[{base64:Buffer.from('not photo').toString('base64')}]})));
test('reject excessive JPEG dimensions',()=>{const b=Buffer.from(jpegHeader);b.writeUInt16BE(60000,7);assert.throws(()=>validateRequest({...request(),images:[{base64:b.toString('base64')}]}));});
test('large allowed encoded image does not overflow regex stack',()=>{const b=Buffer.concat([jpegHeader,Buffer.alloc(1_000_000)]);assert.equal(validateRequest({...request(),images:[{base64:b.toString('base64')}]}).images.length,1);});
test('reject overlarge image before decoding',()=>assert.throws(()=>validateRequest({...request(),images:[{base64:'A'.repeat(2_000_004)}]})));
test('reject negative nutrition, string numbers and Infinity',()=>{for(const n of [-1,'123',Infinity,NaN,20001]){const m=meal();m.items[0].nutrition.calories=n;assert.throws(()=>validateEstimate(m));}});
test('reject duplicate IDs',()=>assert.throws(()=>validateEstimate({...meal(),items:[food(),food()]})));
test('reject multiple or blank follow-up questions',()=>{
  const multiple=meal();multiple.questions=['How much?','What oil?'];assert.throws(()=>validateEstimate(multiple));
  const blank=meal();blank.questions=['  '];assert.throws(()=>validateEstimate(blank));
});
test('reject missing or unknown confidence',()=>{const m=meal();m.items[0].confidence='99%';assert.throws(()=>validateEstimate(m));});
test('reject unknown lock IDs',()=>assert.throws(()=>validateRequest({...request(),currentEstimate:meal(),clarification:'half',lockedItemIDs:['unknown']})));
test('reject refinement without correction',()=>assert.throws(()=>validateRequest({...request(),currentEstimate:meal()})));
test('question answer is kept short',()=>assert.throws(()=>validateRequest({...request(),currentEstimate:meal(),clarification:'a'.repeat(161)}),/160/));
test('context length limit is enforced before provider spend',()=>assert.throws(()=>validateRequest({...request(),description:'x'.repeat(8000),clarification:'more'})));
test('provider request uses Responses image input and strict schema',()=>{const r=request();r.images=[{base64:'abc'}];const p=buildProviderBody(r,'gpt-4.1-mini');assert.equal(p.store,false);assert.equal(p.text.format.type,'json_schema');assert.equal(p.text.format.strict,true);assert.equal(p.input[0].content[1].type,'input_image');assert.equal(p.input[0].content[1].detail,'high');assert.equal(p.input[0].content[1].image_url,'data:image/jpeg;base64,abc');});
test('current snapshot, removals and locks are sent as data',()=>{const r={...request(),currentEstimate:meal(),clarification:'half the rice',lockedItemIDs:['rice'],excludedFoods:['Sauce']};const p=buildProviderBody(r,'model');const input=JSON.parse(p.input[0].content[0].text);assert.deepEqual(input.currentEstimate,meal());assert.deepEqual(input.excludedFoods,['Sauce']);assert.equal(input.clarification,'half the rice');});
test('output parsing skips non-message items',()=>assert.deepEqual(decodeProviderResponse(completed(meal())),meal()));
test('refusal and truncated output fail explicitly',()=>{assert.throws(()=>decodeProviderResponse({status:'incomplete',output:[]}),/incomplete/);assert.throws(()=>decodeProviderResponse({status:'completed',output:[{type:'message',content:[{type:'refusal',refusal:'No'}]}]}),/could not estimate/);});
test('malformed provider JSON is not trusted',()=>assert.throws(()=>decodeProviderResponse({status:'completed',output:[{type:'message',content:[{type:'output_text',text:'not json'}]}]}),/invalid/));
test('locked values preserved even when model changes them',()=>{const next=meal();next.items[0].nutrition.calories=999;const result=enforceLocks(next,meal(),['rice']);assert.deepEqual(result.items[0],food());assert.equal(next.items[0].nutrition.calories,999);});
test('locked food restored if omitted',()=>{const result=enforceLocks({...meal(),items:[]},meal(),['rice']);assert.deepEqual(result.items,[food()]);});
test('unlocked values remain editable',()=>{const next=meal();next.items[0].nutrition.calories=100;assert.equal(enforceLocks(next,meal(),[]).items[0].nutrition.calories,100);});
test('provider HTTP call uses server secret and no storage',async()=>{let seen;const fake=async(url,options)=>{seen={url,options};return new Response(JSON.stringify(completed(meal())),{status:200});};assert.deepEqual(await estimateMeal(request(),{apiKey:'secret-test-only',model:'gpt-4.1-mini'},fake),meal());assert.equal(seen.url,'https://api.openai.com/v1/responses');assert.equal(seen.options.headers.Authorization,'Bearer secret-test-only');assert.equal(JSON.parse(seen.options.body).store,false);assert.equal(seen.options.redirect,'error');});
test('provider errors are sanitized',async()=>{await assert.rejects(()=>estimateMeal(request(),{apiKey:'test',model:'model'},async()=>new Response('private-food-body',{status:401})),error=>error.status===503&&!error.message.includes('private-food-body'));});
test('provider quota errors do not pretend to be nutrition',async()=>{await assert.rejects(()=>estimateMeal(request(),{apiKey:'test',model:'model'},async()=>new Response('',{status:429})),error=>error.status===503);});
test('invalid provider payload is not forwarded',async()=>{await assert.rejects(()=>estimateMeal(request(),{apiKey:'test',model:'model'},async()=>new Response('garbage',{status:200})),error=>error.status===502);});

test('six photo roles and captions reach provider without duplicate meals',()=>{
  const roles=['plate','nutritionLabel','packaging','menu','leftovers','automatic'];
  const r=validateRequest({...request(),images:roles.map(role=>({base64:jpegHeader.toString('base64'),role,caption:'Evidence for the same meal'}))});
  assert.equal(r.images.length,6);
  const body=buildProviderBody(r,'model');
  const text=JSON.parse(body.input[0].content[0].text);
  assert.equal(text.photoEvidence.length,6);
  assert.equal(text.photoEvidence[1].role,'nutritionLabel');
  assert.equal(body.input[0].content.filter(c=>c.type==='input_image').length,6);
  assert.match(body.instructions,/leftover/i);assert.match(body.instructions,/serving/i);
});
test('old image requests still default role and caption',()=>{
  const r=validateRequest({...request(),images:[{base64:jpegHeader.toString('base64')}]});
  assert.equal(r.images[0].role,'automatic');assert.equal(r.images[0].caption,'');
});
test('invalid role caption and unexpected photo keys refused',()=>{
  for(const extra of [{role:'healthRecord'},{caption:'x'.repeat(241)},{url:'https://example.com/private'},{gps:'not allowed'}])
    assert.throws(()=>validateRequest({...request(),images:[{base64:jpegHeader.toString('base64'),...extra}]}));
});
test('label evidence whitelisted without treating it as verified',()=>{
  const value=meal(); value.items[0].evidence=[{kind:'label',photoNumber:2,detail:'Label says 200 kcal per serving; two servings eaten.',secret:'not allowed'}];
  const output=validateEstimate(value);
  assert.deepEqual(output.items[0].evidence,[{kind:'label',photoNumber:2,detail:'Label says 200 kcal per serving; two servings eaten.'}]);
});
test('evidence out of bounds is rejected',()=>{
  for(const bad of [{kind:'unknown',photoNumber:null,detail:'x'},{kind:'label',photoNumber:7,detail:'x'},{kind:'label',photoNumber:0,detail:'x'},{kind:'label',photoNumber:1.5,detail:'x'},{kind:'label',photoNumber:1,detail:'x'.repeat(401)}]) {
    const value=meal();value.items[0].evidence=[bad]; assert.throws(()=>validateEstimate(value));
  }
});
test('manual locks preserve evidence as well as nutrition',()=>{
  const before=meal();before.items[0].evidence=[{kind:'details',photoNumber:null,detail:'Entered label values.'}];
  const result=enforceLocks({...meal(),items:[]},before,['rice']);
  assert.deepEqual(result.items[0],before.items[0]);
});
test('provider strict schema asks for evidence for each food',()=>{
  const body=buildProviderBody(request(),'model');
  assert.ok(body.text.format.schema.items===undefined); // items belongs under properties
  assert.ok(body.text.format.schema.properties.items.items.required.includes('evidence'));
  assert.equal(body.text.format.schema.properties.questions.maxItems,1);
});

test('locked historical label evidence survives a text-only refinement', async () => {
  const current = meal();
  current.items[0].evidence = [{kind:'label', photoNumber:1, detail:'200 kcal per cup'}];
  const input = {...request(), currentEstimate:current, clarification:'Keep rice', lockedItemIDs:['rice']};
  const result = await estimateMeal(input, {apiKey:'test', model:'test'}, async () =>
    new Response(JSON.stringify(completed(meal())), {status:200}));
  assert.deepEqual(result.items[0].nutrition, current.items[0].nutrition);
  assert.equal(result.items[0].evidence[0].photoNumber, null);
  assert.equal(result.items[0].evidence[0].detail, '200 kcal per cup');
  assert.equal(current.items[0].evidence[0].photoNumber, 1);
});
