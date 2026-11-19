// MRK-9 / MRK-R21.AC1: desktop input-to-paint measurement for a 1 MB document.
// Opt-in: run with `playwright test -c spikes/desktop/playwright.latency.config.mjs`.
// Timing is recorded, not asserted, unless MARKRIGHT_ENFORCE_P95_MS is set.
import {test,expect} from '@playwright/test';
import {mkdirSync,writeFileSync} from 'node:fs';
import {dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {mixedFixture,percentile} from './latency-stats.mjs';

const KEYS=Number(process.env.MARKRIGHT_LATENCY_KEYS||120);
const WARMUP=10;
const outDir=join(dirname(fileURLToPath(import.meta.url)),'build','latency');

test.beforeEach(async({page})=>{await page.goto('/');await page.waitForFunction(()=>window.spike);});

test('1 MB mixed document: keydown to next presented frame',async({page,browserName})=>{
 test.setTimeout(180000);
 const fixture=mixedFixture();
 const caret=fixture.indexOf('Plain prose',Math.floor(fixture.length/2))+6;
 await page.evaluate(({s,c})=>{spike.setSource(s);spike.select(c);spike.focus();},{s:fixture,c:caret});
 // Install the probe: keydown (capture) start time; end time is taken after the
 // next animation frame has rendered (rAF, then a MessageChannel task that runs
 // after that frame's paint). This approximates input-to-paint in one page.
 await page.evaluate(()=>{
  window.__lat={samples:[],pending:null};
  const channel=new MessageChannel();
  channel.port1.onmessage=()=>{const p=window.__lat.pending;if(p===null)return;window.__lat.samples.push(performance.now()-p);window.__lat.pending=null;};
  document.addEventListener('keydown',()=>{window.__lat.pending=performance.now();requestAnimationFrame(()=>channel.port2.postMessage(0));},{capture:true});
  window.__evt=[];
  if(typeof PerformanceObserver!=='undefined'&&PerformanceObserver.supportedEntryTypes?.includes('event')){
   new PerformanceObserver(list=>{for(const e of list.getEntries())if(e.name==='keydown')window.__evt.push(e.duration);}).observe({type:'event',buffered:true,durationThreshold:16});
  }
 });
 let typed='';
 for(let i=0;i<KEYS+WARMUP;i++){
  const ch=String.fromCharCode(97+(i%26));
  typed+=ch;
  await page.keyboard.press(ch);
  await page.waitForFunction(()=>window.__lat.pending===null);
 }
 // Source integrity: every keystroke landed once, at the caret, nothing else changed.
 expect(await page.evaluate(()=>spike.source())).toBe(fixture.slice(0,caret)+typed+fixture.slice(caret));
 const all=await page.evaluate(()=>window.__lat.samples);
 expect(all.length).toBe(KEYS+WARMUP);
 const samples=all.slice(WARMUP).sort((a,b)=>a-b);
 const evt=(await page.evaluate(()=>window.__evt)).sort((a,b)=>a-b);
 const result={issue:'MRK-9',requirement:'MRK-R21.AC1',engine:browserName,headless:true,bytes:fixture.length,keys:samples.length,warmup:WARMUP,
  method:'keydown capture -> requestAnimationFrame -> MessageChannel task',
  ms:{p50:percentile(samples,50),p95:percentile(samples,95),max:samples.at(-1)},
  eventTimingOver16ms:{supported:evt.length>0||await page.evaluate(()=>!!PerformanceObserver.supportedEntryTypes?.includes('event')),count:evt.length,p95:percentile(evt,95)},
  budgetMs:50,recordedAt:new Date().toISOString()};
 mkdirSync(outDir,{recursive:true});
 writeFileSync(join(outDir,`latency-${browserName}.json`),JSON.stringify(result,null,1)+'\n');
 test.info().annotations.push({type:'p95-ms',description:result.ms.p95.toFixed(2)});
 const enforce=Number(process.env.MARKRIGHT_ENFORCE_P95_MS||0);
 if(enforce>0)expect(result.ms.p95).toBeLessThan(enforce);
});
