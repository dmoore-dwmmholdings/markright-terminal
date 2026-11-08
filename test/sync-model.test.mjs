import test from 'node:test';import assert from 'node:assert/strict';import {RevisionModel} from '../src/sync-model.mjs';
function base(){const m=new RevisionModel();m.completeBlob('u','b0');m.putRevision('u','d',{id:'r0',blob:'b0'});m.promote('u','d','r0',null);return m;}
function edit(m,id,parent='r0'){m.completeBlob('u','b'+id);m.putRevision('u','d',{id,parent,blob:'b'+id});}
test('concurrent offline writes retain both candidates, never last-write overwrite',()=>{
 for(const order of [['a','b'],['b','a']]){const m=base();edit(m,'a');edit(m,'b');assert.equal(m.promote('u','d',order[0],'r0').status,'published');assert.equal(m.promote('u','d',order[1],'r0').status,'conflict');assert.equal(m.head('u','d'),order[0]);assert.ok(m.revision('u','d',order[1]));}
});
test('head cannot point at an incomplete blob',()=>{const m=base();m.putRevision('u','d',{id:'r1',parent:'r0',blob:'pending'});assert.throws(()=>m.promote('u','d','r1','r0'),/Incomplete/);assert.equal(m.head('u','d'),'r0');m.completeBlob('u','pending');assert.equal(m.promote('u','d','r1','r0').status,'published');});
test('publication and immutable upload retries are idempotent',()=>{const m=base();edit(m,'a');edit(m,'a');m.promote('u','d','a','r0');assert.equal(m.promote('u','d','a','r0').status,'already-published');assert.throws(()=>m.putRevision('u','d',{id:'a',parent:'r0',blob:'different'}),/Immutable/);});
test('delete versus offline edit never resurrects silently',()=>{
 const m=base();edit(m,'offline');m.putRevision('u','d',{id:'deleted',parent:'r0',tombstone:true});m.promote('u','d','deleted','r0');assert.equal(m.promote('u','d','offline','r0').status,'conflict');assert.equal(m.head('u','d'),'deleted');
 // An explicit restore creates a new revision based on the tombstone.
 edit(m,'restored','deleted');assert.equal(m.promote('u','d','restored','deleted').status,'published');
});
test('tenant and document identity cannot share blobs or revision parents',()=>{const m=base();assert.equal(m.head('other','d'),null);assert.throws(()=>m.putRevision('other','d',{id:'x',parent:'r0',blob:'b0'}),/Unknown/);m.putRevision('other','d',{id:'x',blob:'b0'});assert.throws(()=>m.promote('other','d','x',null),/Incomplete/);assert.throws(()=>m.promote('u','other','r0',null),/Missing/);});
test('caller cannot mutate stored revision after upload',()=>{const m=base();const r=m.revision('u','d','r0');assert.throws(()=>{r.blob='evil';},TypeError);assert.equal(m.revision('u','d','r0').blob,'b0');});
test('all edit/edit/delete publication orders preserve one winner and every candidate',()=>{
 const permutations=items=>items.length===0?[[]]:items.flatMap((x,i)=>permutations(items.filter((_,j)=>j!==i)).map(rest=>[x,...rest]));
 for(const order of permutations(['a','b','deleted'])){
  const m=base();edit(m,'a');edit(m,'b');m.putRevision('u','d',{id:'deleted',parent:'r0',tombstone:true});
  const results=order.map(id=>m.promote('u','d',id,'r0'));
  assert.deepEqual(results.map(r=>r.status),['published','conflict','conflict']);assert.equal(m.head('u','d'),order[0]);
  for(const id of order)assert.ok(m.revision('u','d',id));
 }
});
