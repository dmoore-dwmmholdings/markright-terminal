import test,{after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';import fs from 'node:fs';
import {initializeTestEnvironment,assertFails,assertSucceeds} from '@firebase/rules-unit-testing';
import {doc,setDoc,getDoc,deleteDoc} from 'firebase/firestore';
// Fail closed: this executable must never use a production endpoint/project.
assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:18080');
const env=await initializeTestEnvironment({projectId:'demo-markright-spike',firestore:{host:'127.0.0.1',port:18080,rules:fs.readFileSync(new URL('./firestore.rules',import.meta.url),'utf8')}});
after(()=>env.cleanup());beforeEach(()=>env.clearFirestore());
const path=(tenant,type,id)=>`tenants/${tenant}/collections/c/${type}/${id}`;
const db=uid=>env.authenticatedContext(uid).firestore();
async function verified(id){await env.withSecurityRulesDisabled(async ctx=>setDoc(doc(ctx.firestore(),path('alice','verifiedBlobs',id)),{complete:true}));}
async function revision(database,id,parent=null,blob='blob0',tombstone=false,document='document'){return setDoc(doc(database,path('alice','revisions',id)),{document,parent,blob,tombstone});}
async function base(){const a=db('alice');await verified('blob0');await revision(a,'r0');await setDoc(doc(a,path('alice','heads','document')),{revision:'r0'});return a;}
test('owner can publish verified complete revision; other users and anonymous cannot read',async()=>{
 const a=await base();await assertSucceeds(getDoc(doc(a,path('alice','heads','document'))));
 await assertFails(getDoc(doc(db('bob'),path('alice','heads','document'))));
 await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),path('alice','heads','document'))));
 await assertFails(setDoc(doc(db('bob'),path('alice','heads','document')),{revision:'r0'}));
});
test('client cannot forge completion or publish missing blob',async()=>{
 const a=db('alice');await revision(a,'r0');
 await assertFails(setDoc(doc(a,path('alice','verifiedBlobs','blob0')),{complete:true}));
 await assertFails(setDoc(doc(a,path('alice','heads','document')),{revision:'r0'}));
});
test('revisions are immutable and parent must belong to same document',async()=>{
 const a=await base();await assertFails(revision(a,'r0',null,'altered'));
 await assertFails(deleteDoc(doc(a,path('alice','revisions','r0'))));
 await assertFails(revision(a,'other','r0','blob0',false,'different-document'));
});
test('concurrent sibling heads cannot silently overwrite each other',async()=>{
 const a=await base();await revision(a,'a','r0');await revision(a,'b','r0');
 const outcomes=await Promise.allSettled(['a','b'].map(revision=>setDoc(doc(a,path('alice','heads','document')),{revision})));
 assert.equal(outcomes.filter(r=>r.status==='fulfilled').length,1);
 assert.equal(outcomes.filter(r=>r.status==='rejected'&&r.reason.code==='permission-denied').length,1);
 for(const id of ['a','b'])assert.ok((await getDoc(doc(a,path('alice','revisions',id)))).exists());
});
test('tombstone prevents stale resurrection and permits explicit restore',async()=>{
 const a=await base();await revision(a,'old','r0');await revision(a,'deleted','r0',null,true);
 await assertSucceeds(setDoc(doc(a,path('alice','heads','document')),{revision:'deleted'}));
 await assertFails(setDoc(doc(a,path('alice','heads','document')),{revision:'old'}));
 await revision(a,'restore','deleted');await assertSucceeds(setDoc(doc(a,path('alice','heads','document')),{revision:'restore'}));
});
test('unknown fields, wrong document head and physical deletion fail closed',async()=>{
 const a=await base();await assertFails(setDoc(doc(a,path('alice','heads','document')),{revision:'r0',admin:true}));
 await assertFails(setDoc(doc(a,path('alice','heads','other')),{revision:'r0'}));
 await assertFails(deleteDoc(doc(a,path('alice','heads','document'))));
});
test('malformed metadata and unverified completion records are rejected',async()=>{
 const a=db('alice');
 for(const value of [{document:'d'}, {document:'d',parent:null,blob:'../outside',tombstone:false}, {document:'d',parent:null,blob:'blob',tombstone:'false'}, {document:'x'.repeat(129),parent:null,blob:'blob',tombstone:false}]){
  await assertFails(setDoc(doc(a,path('alice','revisions','bad')),value));
 }
 await env.withSecurityRulesDisabled(async ctx=>setDoc(doc(ctx.firestore(),path('alice','verifiedBlobs','blob0')),{complete:false}));
 await revision(a,'r0');await assertFails(setDoc(doc(a,path('alice','heads','document')),{revision:'r0'}));
});
test('same head retry succeeds but cross-collection parent is not recognized',async()=>{
 const a=await base();await assertSucceeds(setDoc(doc(a,path('alice','heads','document')),{revision:'r0'}));
 await assertFails(setDoc(doc(a,'tenants/alice/collections/other/revisions/r1'),{document:'document',parent:'r0',blob:'blob0',tombstone:false}));
});
