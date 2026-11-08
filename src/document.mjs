import {unified} from 'unified';
import remarkParse from 'remark-parse';
import remarkGfm from 'remark-gfm';
import {scan} from './scan.mjs';
const parser = unified().use(remarkParse).use(remarkGfm);
/** Reference-parser spike. Returns AST/source only, never renders HTML or runs code. */
export function analyze(source, options = {}) {
  // Apply quota/type validation before parser allocation.
  scan(source, {...options, extension:'.md'});
  const markdown = parser.parse(source);
  if (options.extension && options.extension !== '.mrk') return {source, markdown, nodes:[], diagnostics:[]};
  const blocked = [];
  for (const node of markdown.children) {
    const isExtensionFence = node.type === 'code' && ['markright-data','markright-js'].includes(node.lang);
    if (node.type !== 'paragraph' && !isExtensionFence) blocked.push([node.position.start.offset,node.position.end.offset]);
    // Multiline inline constructs own their contents too: a column-zero line
    // inside a link, emphasis, inline-code or HTML span is not a block directive.
    if(node.type==='paragraph')for(const child of node.children??[]){
      if(child.type!=='text'&&child.type!=='break')blocked.push([child.position.start.offset,child.position.end.offset]);
    }
  }
  blocked.sort((a,b)=>a[0]-b[0]);
  function ownedAt(offset,ranges){
    let lo=0,hi=ranges.length;
    while(lo<hi){const mid=(lo+hi)>>>1;if(ranges[mid][0]<=offset)lo=mid+1;else hi=mid;}
    return lo>0&&ranges[lo-1][1]>offset;
  }
  const chars=source.split('');
  for(const [start,end] of blocked)for(let i=start;i<end;i++)if(chars[i]!=='\r'&&chars[i]!=='\n')chars[i]=' ';
  // Markdown punctuation inside an extension attribute belongs to the extension.
  // Restore candidate lines only when their start is not inside another construct.
  for(const match of source.matchAll(/^:{2,}[^\r\n]*/gm)){
    if(!ownedAt(match.index,blocked))for(let i=match.index;i<match.index+match[0].length;i++)chars[i]=source[i];
  }
  const masked=chars.join('');
  const result=scan(masked, options);
  const lineStarts = [0];
  for (let i=0;i<source.length;i++) {if(source[i]==='\r'){if(source[i+1]==='\n')i++;lineStarts.push(i+1);}else if(source[i]==='\n')lineStarts.push(i+1);}
  function lineAt(offset) {
    let lo=0, hi=lineStarts.length;
    while(lo<hi) { const mid=(lo+hi)>>>1; if(lineStarts[mid]<=offset)lo=mid+1;else hi=mid; }
    return lo;
  }
  function visit(node) {
    if(['paragraph','heading','tableCell'].includes(node.type)){
      const protectedRanges=[];
      function protect(child){
        if(['inlineCode','html','link','image','definition'].includes(child.type)){
          protectedRanges.push([child.position.start.offset,child.position.end.offset]);return;
        }
        for(const c of child.children??[])protect(c);
      }
      protect(node);protectedRanges.sort((a,b)=>a[0]-b[0]);
      const start=node.position.start.offset;
      const raw=source.slice(start,node.position.end.offset);
      for(const match of raw.matchAll(/:file\[([^\]\r\n]*)\]\{([^}\r\n]*)\}/g)){
        const position=start+match.index;
        if(ownedAt(position,protectedRanges))continue;
        let slashes=0;
        for(let j=match.index-1;j>=0&&raw[j]==='\\';j--)slashes++;
        if(slashes%2)continue;
        const attrs=match[2].match(/^src="([^"\x00-\x1f]+)"(?: display="(card|inline)")?$/);
        const loc={start:position,end:position+match[0].length,line:lineAt(position)};
        if(!attrs||!match[1]||match[1].includes('\\'))result.diagnostics.push({code:'invalid-file-card',...loc});
        else result.nodes.push({type:'file',label:match[1],src:attrs[1],display:attrs[2]??'card',...loc});
      }
      return;
    }
    for(const child of node.children??[])visit(child);
  }
  visit(markdown);
  result.nodes.sort((a,b)=>a.start-b.start);
  return {...result,source,markdown};
}
