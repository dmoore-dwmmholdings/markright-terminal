import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {micromark} from 'micromark';
import {analyze} from '../src/document.mjs';
const corpus=JSON.parse(readFileSync(new URL('../fixtures/commonmark-0.31.2.json',import.meta.url)));
test(`CommonMark 0.31.2 reference compiler: ${corpus.length} upstream examples`,()=>{
 for(const item of corpus){
  // Normative trusted fixture comparison only: produced HTML is never rendered.
  assert.equal(micromark(item.markdown,{allowDangerousHtml:true,allowDangerousProtocol:true}),item.html,`example ${item.example}: ${item.section}`);
 }
});
test('all upstream Markdown inputs remain extension-opaque with bounded source ranges',()=>{
 for(const item of corpus){
  const parsed=analyze(item.markdown,{extension:'.md'});
  assert.equal(parsed.source,item.markdown);assert.equal(parsed.nodes.length,0);
  function walk(n){if(n.position){let {start,end}=n.position;assert.ok(start.offset>=0 && end.offset>=start.offset && end.offset<=item.markdown.length,`range example ${item.example}`);}for(const child of n.children??[])walk(child);}
  walk(parsed.markdown);
 }
});
