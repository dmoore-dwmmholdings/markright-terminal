import test from 'node:test';import assert from 'node:assert/strict';
import {analyze} from '../src/document.mjs';import {createProjection} from '../src/editor-projection.mjs';
test('deterministic mixed-syntax corpus preserves bounded source coordinates',()=>{
 let seed=0x4d524b;const random=()=>{seed=(Math.imul(seed,1664525)+1013904223)>>>0;return seed;};
 const parts=['😀','e\u0301','\r','\n','\r\n','plain','`','```','*','[',']','(',')','> ','- ','|x|y|','::include{src="x"}',':file[Board]{src="x"}',':::snippet{id="s"}',':::','```markright-js id="c"','<div>'];
 for(let example=0;example<200;example++){
  let source='';for(let j=0;j<40;j++)source+=parts[random()%parts.length];
  const result=analyze(source);assert.equal(result.source,source);
  for(const item of [...result.nodes,...result.diagnostics]){
   assert.ok(Number.isInteger(item.start)&&Number.isInteger(item.end));assert.ok(item.start>=0&&item.start<=item.end&&item.end<=source.length);
  }
  const reveal=createProjection(source,result.markdown);
  for(const offset of [0,source.length]){const r=reveal({start:offset,end:offset});assert.ok(r.start<=offset&&r.end>=offset);assert.ok(r.start>=0&&r.end<=source.length);}
 }
});
