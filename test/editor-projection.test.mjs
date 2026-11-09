import test from 'node:test';import assert from 'node:assert/strict';
import {analyze} from '../src/document.mjs';import {revealRange} from '../src/editor-projection.mjs';
const reveal=(s,a,b=a,opts)=>revealRange(s,analyze(s).markdown,{start:a,end:b},opts);
test('ordinary active line leaves adjacent preview source alone',()=>{const s='one\r\ntwo\r\nthree';const r=reveal(s,6);assert.equal(s.slice(r.start,r.end),'two\r\n');assert.deepEqual(r.selection,{start:6,end:6});});
test('code fences and table cells expose their entire atomic block',()=>{
 for(const s of ['before\n\n```js\nx=1;\ny=2;\n```\n\nafter','before\n\n|a|b|\n|-|-|\n|x|y|\n\nafter']){
 const r=reveal(s,s.indexOf(s.includes('```')?'x=1':'|x|')+1);
 assert.equal(s.slice(r.start,r.end).trim(),s.split('\n\n')[1]);
 }
});
test('selection ending at next line excludes that next line',()=>{const r=reveal('one\ntwo\nthree',1,4);assert.equal(r.end,4);});
test('empty last line remains editable',()=>{const r=reveal('a\n',2);assert.equal(r.start,2);assert.equal(r.end,2);});
test('IME composition defers projection without replacing source',()=>assert.deepEqual(reveal('text',2,2,{composing:true}),{deferred:true}));
test('invalid selections and split emoji surrogate pairs reject',()=>{for(const p of [-1,1,4])assert.throws(()=>reveal('😀x',p),RangeError);assert.equal(reveal('😀x',2).selection.start,2);});
test('empty first line retains zero origin',()=>assert.equal(reveal('\ntext',0).start,0));
test('standalone CR line boundaries retain exact source',()=>{const s='a\rb\rc';const r=reveal(s,2);assert.equal(s.slice(r.start,r.end),'b\r');});
test('unclosed fences own the final empty EOF line',()=>{
 for(const newline of ['\n','\r\n','\r'])for(const fence of ['```js','~~~js'])for(const body of ['',`value${newline}`,newline]){
  const s=`before${newline}${newline}${fence}${newline}${body}`;
  const r=reveal(s,s.length);
  assert.equal(r.start,s.indexOf(fence));assert.equal(r.end,s.length);
  assert.deepEqual(r.selection,{start:s.length,end:s.length});
 }
});
test('closed fences, tables and indented code leave the following empty line separate',()=>{
 for(const newline of ['\n','\r\n','\r'])for(const lines of [['```js','value','```'],['~~~js','value','~~~'],['|a|b|','|-|-|','|x|y|'],['    value']]){
  const block=lines.join(newline),s=block+newline;
  const r=reveal(s,s.length);
  assert.equal(r.start,s.length);assert.equal(r.end,s.length);
  const end=reveal(block,block.length);
  assert.equal(end.start,0);assert.equal(end.end,block.length);
 }
});
test('container ownership distinguishes an EOF list fence from a completed quote',()=>{
 const quote='> ```\n> x\n',list='- ```\n  x\n';
 assert.equal(reveal(quote,quote.length).start,quote.length);
 assert.equal(reveal(list,list.length).start,list.indexOf('```'));
});
