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
  }
  let masked = '', cursor = 0;
  for (const [start,end] of blocked) {
    masked += source.slice(cursor,start) + source.slice(start,end).replace(/[^\r\n]/g,' '); cursor=end;
  }
  masked += source.slice(cursor);
  const result=scan(masked, options);
  const lineStarts = [0];
  for (let i=0;i<source.length;i++) if(source[i]==='\n') lineStarts.push(i+1);
  function lineAt(offset) {
    let lo=0, hi=lineStarts.length;
    while(lo<hi) { const mid=(lo+hi)>>>1; if(lineStarts[mid]<=offset)lo=mid+1;else hi=mid; }
    return lo;
  }
  function visit(node, excluded = false) {
    const skip = excluded || ['code','inlineCode','html','link','image','definition'].includes(node.type);
    if (!skip && node.type === 'text') {
      const start = node.position.start.offset;
      const raw = source.slice(start,node.position.end.offset);
      for (const match of raw.matchAll(/:file\[([^\]\r\n]*)\]\{([^}\r\n]*)\}/g)) {
        let slashes = 0;
        for(let j=match.index-1;j>=0 && raw[j]==='\\';j--) slashes++;
        if (slashes % 2) continue;
        const attrs = match[2].match(/^src="([^"\x00-\x1f]+)"(?: display="(card|inline)")?$/);
        const position = start + match.index;
        const loc = {start:position,end:position+match[0].length,line:lineAt(position)};
        if (!attrs || !match[1] || match[1].includes('\\')) result.diagnostics.push({code:'invalid-file-card',...loc});
        else result.nodes.push({type:'file',label:match[1],src:attrs[1],display:attrs[2]??'card',...loc});
      }
    }
    for(const child of node.children??[])visit(child,skip);
  }
  visit(markdown);
  result.nodes.sort((a,b)=>a.start-b.start);
  return {...result,source,markdown};
}
