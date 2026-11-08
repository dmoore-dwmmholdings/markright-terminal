import {performance} from 'node:perf_hooks';
import {analyze} from '../src/document.mjs';import {revealRange} from '../src/editor-projection.mjs';
const source=('## Section\n\nplain text **bold** and [link](./file)\n\n').repeat(20000).slice(0,1000000);
const begin=performance.now();const doc=analyze(source);const parseMs=performance.now()-begin;
const timings=[];
for(let i=0;i<100;i++){const offset=Math.floor(i*source.length/100);const start=performance.now();revealRange(source,doc.markdown,{start:offset,end:offset});timings.push(performance.now()-start);}
timings.sort((a,b)=>a-b);
console.log(JSON.stringify({node:process.version,bytes:Buffer.byteLength(source),fullParseMs:parseMs,cachedAstRevealP50Ms:timings[50],cachedAstRevealP95Ms:timings[95],note:'Headless model only. Not UI latency, incremental parsing, IME or accessibility acceptance.'},null,2));
