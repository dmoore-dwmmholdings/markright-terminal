import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {micromark} from 'micromark';
import {gfm,gfmHtml} from 'micromark-extension-gfm';
import {analyze} from '../src/document.mjs';
const cases=JSON.parse(fs.readFileSync(new URL('../fixtures/gfm-0.29.json',import.meta.url)));
test('GFM 0.29 extension reference differences remain explicitly bounded',()=>{
 const failed=[];
 for(const c of cases){
  // Inert normative HTML string comparisons only; NEVER mount output in a view.
  const out=micromark(c.markdown,{extensions:[gfm()],htmlExtensions:[gfmHtml()],allowDangerousHtml:true,allowDangerousProtocol:true});
  if(out!==c.html)failed.push(c.example);
 }
 assert.equal(cases.length,24);
 assert.deepEqual(failed,[279,280,628]);
});
test('GFM corpus stays extension-opaque in Markdown mode',()=>{
 for(const c of cases){const r=analyze(c.markdown,{extension:'.md'});assert.equal(r.source,c.markdown);assert.deepEqual(r.nodes,[]);}
});
