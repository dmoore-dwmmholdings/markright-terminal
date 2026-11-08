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
  return {...result,source,markdown};
}
