import test from 'node:test';import assert from 'node:assert/strict';
import {getQuickJS} from 'quickjs-emscripten';
const engine=await getQuickJS();
// Test-only harness, not a production scripting API or isolation assurance.
function probe(code){
 const runtime=engine.newRuntime();runtime.setMemoryLimit(8*1024*1024);runtime.setMaxStackSize(256*1024);
 let ticks=0;const deadline=Date.now()+100;
 runtime.setInterruptHandler(()=>++ticks>1000||Date.now()>deadline);
 const vm=runtime.newContext();
 try{
  const result=vm.evalCode(code);
  if(result.error){result.error.dispose();return {error:true};}
  try{
   // Only primitive short results from authored test fixtures cross to host.
   const type=vm.typeof(result.value);
   if(type!=='string'&&type!=='number'&&type!=='boolean')return {error:true};
   return {value:vm.dump(result.value)};
  }finally{result.value.dispose();}
 }finally{vm.dispose();runtime.dispose();}
}
test('isolated runtime exposes no ambient network, filesystem or DOM',()=>assert.equal(probe("[typeof fetch,typeof require,typeof process,typeof document,typeof WebSocket].join(',')").value,'undefined,undefined,undefined,undefined,undefined'));
test('infinite loop interrupted within runtime budget',()=>assert.equal(probe('while(true){}').error,true));
test('memory amplification fails within configured heap',()=>assert.equal(probe('let a=[];while(true)a.push(new Array(10000).fill(42));').error,true));
test('recursive stack growth is bounded',()=>assert.equal(probe('function f(){return f()+1;}f()').error,true));
test('guest pollution cannot mutate host or next evaluation',()=>{assert.equal(probe('Object.prototype.markrightPolluted=1;"ok"').value,'ok');assert.equal({}.markrightPolluted,undefined);assert.equal(probe('typeof ({}).markrightPolluted').value,'undefined');});
test('64-bit integer candidate retains exact values',()=>assert.equal(probe('(0xffffffffffffffffn >> 60n).toString()').value,'15'));
