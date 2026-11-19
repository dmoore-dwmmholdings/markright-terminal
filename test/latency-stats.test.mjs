import test from 'node:test';
import assert from 'node:assert/strict';
import {mixedFixture,percentile} from '../spikes/desktop/latency-stats.mjs';

test('percentile uses nearest-rank on sorted samples',()=>{
 const s=Array.from({length:100},(_,i)=>i+1);
 assert.equal(percentile(s,50),50);
 assert.equal(percentile(s,95),95);
 assert.equal(percentile(s,100),100);
 assert.equal(percentile([7],95),7);
 assert.ok(Number.isNaN(percentile([],95)));
});

test('mixed fixture is exactly the requested size and contains every construct',()=>{
 const f=mixedFixture();
 assert.equal(f.length,1000000);
 for(const part of ['# Section','**bold**','*italic*','~~strike~~','](https://example.invalid/)','```js','| a | b |','> quoted','- item'])assert.ok(f.includes(part),part);
 assert.equal(mixedFixture(10).length,10);
});
