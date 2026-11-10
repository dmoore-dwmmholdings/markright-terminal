import test from 'node:test';
import assert from 'node:assert/strict';
import {analyze} from '../src/document.mjs';
const descendants=n=>[n,...(n.children??[]).flatMap(descendants)];
test('reference AST maps an initial BOM into exact source offsets and physical columns',()=>{
 for(const newline of ['\n','\r\n','\r'])for(const body of ['', '😀', '# Heading'+newline+newline+'A **bold** [link](./a).'+newline+newline+'|a|b|'+newline+'|-|-|'+newline+'|x|y|'+newline+newline+'```js'+newline+'x'+newline+'```'+newline]){
  const source='\uFEFF'+body;
  for(const extension of ['.mrk','.md']){
   const baseline=descendants(analyze(body,{extension}).markdown),result=analyze(source,{extension}),mapped=descendants(result.markdown);
   assert.equal(result.source,source);assert.equal(mapped.length,baseline.length);
   for(let i=0;i<mapped.length;i++){
    assert.equal(mapped[i].type,baseline[i].type);
    for(const side of ['start','end']){
     const expected=i===0&&side==='start'?{line:1,column:1,offset:0}:{...baseline[i].position[side],offset:baseline[i].position[side].offset+1,column:baseline[i].position[side].column+(baseline[i].position[side].line===1?1:0)};
     assert.deepEqual(mapped[i].position[side],expected,`${extension} ${mapped[i].type}.${side}`);
    }
   }
  }
 }
 const doubled=analyze('\uFEFF\uFEFFx');
 assert.equal(doubled.markdown.children[0].children[0].value,'\uFEFFx');
 assert.equal(doubled.markdown.children[0].position.start.offset,1);
 assert.equal(doubled.markdown.position.end.offset,3);
 const unsupported=analyze('\uFEFF<!-- markright: 9.9 -->\n😀');
 assert.deepEqual(unsupported.nodes,[]);assert.equal(unsupported.markdown.position.end.offset,unsupported.source.length);
});
test('BOM-aware AST ownership retains file cards and keeps nested markup inert',()=>{
 for(const newline of ['\n','\r\n','\r']){
  const source='\uFEFF:file[A]{src="x"}'+newline+newline+':file[B]{src="y"}';
  const result=analyze(source);
  assert.deepEqual(result.nodes.map(n=>[n.label,n.src,n.line]),[['A','x',1],['B','y',3]]);
  for(const node of result.nodes)assert.equal(source.slice(node.start,node.end),`:file[${node.label}]{src="${node.src}"}`);
  for(const body of ['`:file[A]{src="x"}`','[:file[A]{src="x"}](./link)','<div>'+newline+'::include{src="x"}'+newline+'</div>','```'+newline+':file[A]{src="x"}'+newline+'::include{src="x"}'+newline+'```']){
   assert.deepEqual(analyze('\uFEFF'+body).nodes,[],body);
  }
 }
});
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
test('multiline inline constructs cannot expose block directives',()=>{
 for(const wrap of [s=>'`first\n'+s+'\nlast`',s=>'*first\n'+s+'\nlast*',s=>'[first\n'+s+'\nlast](./x)']){
  const r=analyze(wrap('::include{src="x"}'));assert.equal(r.nodes.length,0);assert.equal(r.diagnostics.length,0);
 }
});
test('lone CR documents preserve directive and card positions',()=>{
 const source='first\r::include{src="x"}\r\r:file[Board]{src="x"}';const r=analyze(source);
 assert.equal(r.source,source);assert.deepEqual(r.nodes.map(n=>[n.type,n.line]),[['include',2],['file',4]]);
 for(const n of r.nodes)assert.ok(source.slice(n.start,n.end).startsWith(n.type==='file'?':file':'::include'));
});
test('directive attributes preserve Markdown punctuation rather than masked bytes',()=>{
 for(const path of ['./a*b*.mrk','./a`b`.mrk','https://example.com/a','./a[b](c).mrk']){
  const s=`::include{src="${path}"}`;const r=analyze(s);assert.equal(r.nodes[0]?.src,path);assert.deepEqual(r.diagnostics,[]);
 }
});
test('file cards parse raw syntax despite inline Markdown/autolink splitting',()=>{
 for(const path of ['./a*b*.pdf','./a`b`.pdf','https://example.com/x','./a[b](c).pdf']){
  const s=`:file[Board]{src="${path}"}`;const r=analyze(s);assert.equal(r.nodes[0]?.src,path);assert.deepEqual(r.diagnostics,[]);
 }
});
test('reference-link definitions cannot steal a file-card label',()=>{
 const s=':file[Board]{src="./board.pdf"}\n\n[Board]: https://example.com';const r=analyze(s);assert.equal(r.nodes[0]?.src,'./board.pdf');assert.deepEqual(r.diagnostics,[]);
});
test('existing reference links and images own nested card-shaped text',()=>{
 for(const prefix of ['', '!']){
  const s=`${prefix}[outer :file[Board]{src="x"}][r]\n\n[r]: https://example.com`;assert.equal(analyze(s).nodes.length,0);
 }
});
