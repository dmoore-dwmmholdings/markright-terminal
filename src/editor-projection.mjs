/** Experimental projection planner. Source is authoritative; no widgets or rendering. */
export function createProjection(source, markdown) {
  const lines=[0], blocks=[];
  let eofCodeStart;
  for(let i=0;i<source.length;i++){if(source[i]==='\r'){if(source[i+1]==='\n')i++;lines.push(i+1);}else if(source[i]==='\n')lines.push(i+1);}
  function visit(node){
    if(['table','code'].includes(node.type))blocks.push([node.position.start.offset,node.position.end.offset]);
    // The reference parser includes the final empty EOF line in an unclosed
    // fenced code node. Closed fences and indented code end before that line.
    if(node.type==='code'&&node.position.end.offset===source.length&&lines.at(-1)===source.length)eofCodeStart=node.position.start.offset;
    for(const child of node.children??[])visit(child);
  }
  visit(markdown);blocks.sort((a,b)=>a[0]-b[0]);
  function lineIndex(offset){let lo=0,hi=lines.length;while(lo<hi){const mid=(lo+hi)>>>1;if(lines[mid]<=offset)lo=mid+1;else hi=mid;}return lo-1;}
  return (selection,{composing=false}={}) => {
  if(composing)return {deferred:true}; // Never rebuild a preview during marked-text composition.
  const {start,end}=selection;
  if(!Number.isInteger(start)||!Number.isInteger(end)||start<0||end<start||end>source.length)throw new RangeError('Invalid UTF-16 selection');
  for(const offset of [start,end]){
    if(offset>0 && offset<source.length && /[\uD800-\uDBFF]/.test(source[offset-1]) && /[\uDC00-\uDFFF]/.test(source[offset]))throw new RangeError('Selection splits surrogate pair');
  }
  let from=lines[lineIndex(start)];
  const anchor=end>start?end-1:end;
  let to=lines[lineIndex(anchor)+1]??source.length;
  // Atomic blocks are disjoint in the reference AST; binary search first intersection.
  let lo=0,hi=blocks.length;
  while(lo<hi){const mid=(lo+hi)>>>1;if(blocks[mid][1]<=from)lo=mid+1;else hi=mid;}
  for(let i=lo;i<blocks.length&&blocks[i][0]<to;i++){
    const [a,b]=blocks[i];from=Math.min(from,a);to=Math.max(to,b);
  }
  if(start===end&&start===source.length&&eofCodeStart!==undefined)from=Math.min(from,eofCodeStart);
  return {deferred:false,start:from,end:to,selection:{start,end}};
  };
}
export function revealRange(source,markdown,selection,options){return createProjection(source,markdown)(selection,options);}
