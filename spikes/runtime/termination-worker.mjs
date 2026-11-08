import {parentPort} from 'node:worker_threads';
import {getQuickJS} from 'quickjs-emscripten';
const engine=await getQuickJS();const runtime=engine.newRuntime();
runtime.setMemoryLimit(8*1024*1024);runtime.setMaxStackSize(256*1024);
const vm=runtime.newContext();
parentPort.postMessage('ready');
// Deliberately omit cooperative interruption to prove parent can terminate a stuck VM.
vm.evalCode('while(true){}');
