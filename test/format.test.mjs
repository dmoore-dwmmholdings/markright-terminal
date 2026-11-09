import test from 'node:test';import assert from 'node:assert/strict';import {analyze} from '../src/document.mjs';
test('versionless and explicit 0.1 Markright use the same grammar',()=>{
 for(const header of ['','<!-- markright: 0.1 -->\n','\uFEFF<!-- markright: 0.1 -->\r\n']){
  const s=header+'::include{src="./a*b*.mrk"}';const r=analyze(s);assert.equal(r.formatVersion,'0.1');assert.equal(r.nodes[0].src,'./a*b*.mrk');assert.equal(r.source,s);
 }
});
test('unsupported or malformed declared format fails closed without losing source',()=>{
 for(const header of ['<!-- markright: 0.2 -->','<!-- markright: latest -->','<!--markright: 0.2 -->','<!-- markright : 0.2 -->',' <!-- markright: 0.2 -->']){
  const s=header+'\n::include{src="x"}\n:file[Board]{src="x"}';const r=analyze(s);assert.equal(r.formatVersion,null);assert.deepEqual(r.nodes,[]);assert.equal(r.diagnostics.length,1);assert.equal(r.source,s);
 }
});
test('Markdown cannot opt into extensions with a format marker',()=>{const r=analyze('<!-- markright: 0.1 -->\n::include{src="x"}',{extension:'.md'});assert.deepEqual(r.nodes,[]);assert.deepEqual(r.diagnostics,[]);});
test('BOM is preserved while first-line directive source positions stay exact',()=>{
 const s='\uFEFF::include{src="./a*b*.mrk"}';const r=analyze(s);assert.equal(r.nodes[0].start,1);assert.equal(r.nodes[0].src,'./a*b*.mrk');assert.equal(r.source,s);
});
test('closing braces inside quoted file-card values are not structural delimiters',()=>{
 const s=':file[Board]{src="./a}b.pdf"}';const r=analyze(s);assert.equal(r.nodes[0]?.src,'./a}b.pdf');assert.deepEqual(r.diagnostics,[]);
});
