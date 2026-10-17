import test from 'node:test';
import assert from 'node:assert/strict';
import {estimateMeal} from '../estimate.mjs';
const input={description:'Synthetic eggs',images:[],lockedItemIDs:[],excludedFoods:[],currentEstimate:null};
for(const status of [401,403,429,500]) {
  test(`non-success upstream ${status} cancels its unread response body`,async()=>{
    let cancelled=false,pulls=0;
    const stream=new ReadableStream({pull(c){pulls++;c.enqueue(new Uint8Array(100_000));},cancel(){cancelled=true;}});
    await assert.rejects(()=>estimateMeal(input,{apiKey:'synthetic',model:'synthetic'},async()=>new Response(stream,{status})));
    assert.ok(cancelled,'discard upstream error body instead of leaving its socket/stream alive');
    assert.ok(pulls<=2,'do not read a private or oversized upstream error body');
  });
}
