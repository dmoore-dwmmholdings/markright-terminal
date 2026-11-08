import test from 'node:test';import assert from 'node:assert/strict';
import {Worker} from 'node:worker_threads';import {once} from 'node:events';
test('parent terminates a noncooperating guest worker',{timeout:10000},async()=>{
 const worker=new Worker(new URL('../spikes/runtime/termination-worker.mjs',import.meta.url));
 const guard=setTimeout(()=>worker.terminate(),8000);
 try{
  const [message]=await once(worker,'message');assert.equal(message,'ready');
  await new Promise(resolve=>setTimeout(resolve,50));
  const start=performance.now();const code=await worker.terminate();
  assert.equal(code,1);assert.ok(performance.now()-start<2000,'Worker termination exceeded spike bound');
 }finally{clearTimeout(guard);await worker.terminate();}
});
