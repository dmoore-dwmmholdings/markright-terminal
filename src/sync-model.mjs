// Pure in-memory protocol model. NOT Firebase, authorization rules, or encryption.
export class RevisionModel {
  #blobs=new Set(); #revisions=new Map(); #heads=new Map();
  key(...parts){return JSON.stringify(parts);}
  completeBlob(tenant,digest){this.#blobs.add(this.key(tenant,digest));}
  putRevision(tenant,document,revision){
    const {id,parent=null,blob=null,tombstone=false}=revision;
    if(!id || (tombstone ? blob!==null : !blob))throw new Error('Invalid revision');
    if(parent!==null&&!this.#revisions.has(this.key(tenant,document,parent)))throw new Error('Unknown parent');
    const normalized=Object.freeze({id,parent,blob,tombstone});
    const key=this.key(tenant,document,id),existing=this.#revisions.get(key);
    if(existing&&JSON.stringify(existing)!==JSON.stringify(normalized))throw new Error('Immutable revision');
    this.#revisions.set(key,normalized);
  }
  head(tenant,document){return this.#heads.get(this.key(tenant,document))??null;}
  promote(tenant,document,id,expected){
    const revision=this.#revisions.get(this.key(tenant,document,id));
    if(!revision)throw new Error('Missing revision');
    if(!revision.tombstone&&!this.#blobs.has(this.key(tenant,revision.blob)))throw new Error('Incomplete blob');
    const current=this.head(tenant,document);
    // A lost acknowledgment can safely retry the same publication.
    if(current===id)return {status:'already-published',head:current};
    if(current!==expected||revision.parent!==expected)return {status:'conflict',head:current,candidate:id};
    this.#heads.set(this.key(tenant,document),id);
    return {status:'published',head:id};
  }
  revision(tenant,document,id){return this.#revisions.get(this.key(tenant,document,id))??null;}
}
