import test from 'node:test';
import assert from 'node:assert/strict';
import {analyze} from '../src/document.mjs';
const descendants=n=>[n,...(n.children??[]).flatMap(descendants)];
test('real reference AST covers baseline inline/block Markdown and GFM',()=>{
 const text='# Heading\n\n*em* **strong** ~~gone~~ [link](a) ![alt](b) <https://example.com>\n\n> quote\n\n1. one\n2. two\n\n- [x] checked\n\n|x|y|\n|-|-|\n|1|2|\n\n---\n\n```js\nconst a=1\n```';
 const types=new Set(descendants(analyze(text).markdown).map(x=>x.type));
 for(const type of ['heading','emphasis','strong','delete','link','image','blockquote','list','table','thematicBreak','code'])assert.ok(types.has(type),type);
 assert.ok(descendants(analyze(text).markdown).some(x=>x.checked===true));
});
test('container blocks cannot leak directives from list/quote/fence contexts',()=>{
 for(const text of ['- ```\n  example\n  ::include{src="x"}\n  ```','```\n::include{src="x"}\n```','    ::include{src="x"}']) {
  assert.equal(analyze(text).nodes.length,0);
 }
 assert.equal(analyze('> ::include{src="x"}\n> more').nodes.length,0);
});
test('HTML blocks stay inert source and hide directives',()=>{
 const s='<div>\n::include{src="x"}\n</div>'; const r=analyze(s);assert.equal(r.nodes.length,0);assert.equal(r.source,s);assert.equal(r.markdown.children[0].type,'html');
});
test('extension fences survive parser integration with original ranges',()=>{
 const s='😀\r\n\r\n```markright-data id="x"\r\n{"value":1}\r\n```\r\n';const r=analyze(s);assert.equal(r.nodes.length,1);assert.equal(s.slice(r.nodes[0].contentStart,r.nodes[0].contentEnd),'{"value":1}\r\n');
});
test('Markdown mode retains extension syntax with no interpreted nodes',()=>assert.equal(analyze('::include{src="a"}',{extension:'.md'}).nodes.length,0));
test('fenced snippets do not open regions',()=>assert.equal(analyze('```\n:::snippet{id="x"}\n```').diagnostics.length,0));
test('limits apply before Markdown parsing',()=>assert.throws(()=>analyze('😀',{maxBytes:3}),RangeError));
test('typed file cards are source-mapped but never resolved',()=>{
 const s='😀 :file[Board]{src="./board%20one.pdf" display="card"}';const n=analyze(s).nodes[0];
 assert.equal(n.type,'file');assert.equal(n.src,'./board%20one.pdf');assert.equal(s.slice(n.start,n.end),':file[Board]{src="./board%20one.pdf" display="card"}');
});
test('file cards honor escapes, code, and link nesting',()=>{
 for(const s of ['\\:file[Board]{src="a"}','`:file[Board]{src="a"}`','[:file[Board]{src="a"}](https://example.com)','```\n:file[Board]{src="a"}\n```']) assert.equal(analyze(s).nodes.length,0,s);
 assert.equal(analyze('\\\\:file[Board]{src="a"}').nodes.length,1);
});
test('malformed complete cards diagnose and retain source',()=>{
 const s=':file[Board]{src="a" execute="true"}';const r=analyze(s);assert.equal(r.nodes.length,0);assert.equal(r.diagnostics[0].code,'invalid-file-card');assert.equal(r.source,s);
});

test('many inline cards retain line offsets without repeated prefix scans', () => {
  const source=Array.from({length:2000},(_,i)=>`:file[item${i}]{src="./${i}.pdf"}`).join('\r\n');
  const result=analyze(source);
  assert.equal(result.nodes.length,2000);
  for(let i=0;i<2000;i++) {
    assert.equal(result.nodes[i].line,i+1);
    assert.equal(source.slice(result.nodes[i].start,result.nodes[i].end),`:file[item${i}]{src="./${i}.pdf"}`);
  }
});
