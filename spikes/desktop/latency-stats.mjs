// Pure helpers for the MRK-9 desktop latency measurement (unit-tested in test/latency-stats.test.mjs).
// Mixed Markdown so the decorations, atomic fences and tables are all present.
export function mixedFixture(bytes=1000000){
 const unit='# Section heading\n\nPlain prose with **bold**, *italic*, ~~strike~~ and a [link](https://example.invalid/).\n\n```js\nconst value = 1;\n```\n\n| a | b |\n| - | - |\n| 1 | 2 |\n\n> quoted line\n\n- item one\n- item two\n\n';
 return unit.repeat(Math.ceil(bytes/unit.length)).slice(0,bytes);
}

export function percentile(sorted,p){
 if(!sorted.length)return NaN;
 const rank=Math.ceil((p/100)*sorted.length)-1;
 return sorted[Math.min(sorted.length-1,Math.max(0,rank))];
}
