/** Experimental projection planner. Source is authoritative; no widgets or rendering. */
export function revealRange(source, markdown, selection, {composing=false}={}) {
  if(composing)return {deferred:true}; // Never rebuild a preview during marked-text composition.
  const {start,end}=selection;
  if(!Number.isInteger(start)||!Number.isInteger(end)||start<0||end<start||end>source.length)throw new RangeError('Invalid UTF-16 selection');
  for(const offset of [start,end]){
    if(offset>0 && offset<source.length && /[\uD800-\uDBFF]/.test(source[offset-1]) && /[\uDC00-\uDFFF]/.test(source[offset]))throw new RangeError('Selection splits surrogate pair');
  }
  let from=start===0?0:source.lastIndexOf('\n',start-1)+1;
  // A nonempty selection ending at next line's start does not include that line.
  const anchor=end>start?end-1:end;
  const newline=source.indexOf('\n',anchor);
  let to=newline<0?source.length:newline+1;
  const blocks=[];
  function visit(node){
    if(['table','code'].includes(node.type))blocks.push([node.position.start.offset,node.position.end.offset]);
    for(const child of node.children??[])visit(child);
  }
  visit(markdown);
  // Expand only structurally atomic blocks touched by selection/active line.
  for(const [a,b] of blocks){if(a<to&&b>from){from=Math.min(from,a);to=Math.max(to,b);}}
  return {deferred:false,start:from,end:to,selection:{start,end}};
}
