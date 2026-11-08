import test from 'node:test';
import assert from 'node:assert/strict';
import {scan} from '../src/scan.mjs';
test('md stays opaque, extensions opt in',()=>assert.equal(scan('::include{src="x"}',{extension:'.md'}).nodes.length,0));
test('preserves UTF16 ranges and CRLF source exactly',()=>{
 const s='😀 café\r\n::include{src="./a b.mrk#snippet=power"}\r\n';const r=scan(s);
 assert.equal(r.source,s);assert.equal(r.nodes[0].start,s.indexOf('::'));assert.equal(r.nodes[0].end,s.length);assert.equal(r.nodes[0].line,2);
});
test('code fences hide directives; matching length and character required',()=>{
 for(const marker of ['````','~~~~']) {const s=marker+'text\n::include{src="hidden"}\n'+marker.slice(0,3)+'\n::include{src="hidden2"}\n'+marker+'\n::include{src="ok"}'; assert.deepEqual(scan(s).nodes.map(x=>x.src),['ok']);}
});
test('escaped and indented directives stay ordinary source',()=>assert.equal(scan('\\::include{src="x"}\n    ::include{src="y"}\n> ::include{src="z"}').nodes.length,0));
test('named snippets preserve original content offsets',()=>{let s=':::snippet{id="power"}\n# Power\n[part](./p.pdf)\n:::\n';let n=scan(s).nodes[0];assert.equal(s.slice(n.contentStart,n.contentEnd),'# Power\n[part](./p.pdf)\n');});
test('unclosed snippets and invalid nesting diagnose without dropping source',()=>{let s=':::snippet{id="a"}\n:::snippet{id="b"}\n';let r=scan(s);assert.equal(r.source,s);assert.deepEqual(r.diagnostics.map(x=>x.code),['invalid-snippet','unclosed-snippet']);});
test('data and script bodies remain inert',()=>{
 let s='```markright-data id="register"\n{"bits":64}\n```\n```markright-js id="decode" inputs="register"\nthrow new Error("MUST NOT EXECUTE");\n```';let r=scan(s);assert.deepEqual(r.nodes.map(x=>x.type),['data','script']);assert.deepEqual(r.nodes[1].inputs,['register']);assert.equal(r.diagnostics.length,0);
});
test('duplicate IDs share document namespace',()=>assert.equal(scan(':::snippet{id="a"}\nx\n:::\n```markright-data id="a"\n{}\n```').diagnostics[0].code,'duplicate-id'));
test('unknown directives preserve text and diagnostic',()=>{let r=scan('::future{x="y"}');assert.equal(r.source,'::future{x="y"}');assert.equal(r.diagnostics[0].code,'unknown-directive');});
test('invalid attributes and unclosed script reject predictably',()=>{assert.equal(scan('```markright-data id="x" inputs="y"\n{}\n```').diagnostics[0].code,'invalid-fence-attributes');assert.equal(scan('```markright-js id="x"\nwhile(true){}').diagnostics[0].code,'unclosed-extension-fence');});
test('quota counts utf8 bytes rather than code units',()=>assert.throws(()=>scan('😀',{maxBytes:3}),RangeError));
test('trailing newline is optional',()=>assert.equal(scan('::include{src="x"}').nodes[0].end,18));
