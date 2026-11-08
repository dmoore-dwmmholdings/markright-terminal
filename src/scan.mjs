/** Experimental MRK-8 lexical spike. Not a Markdown parser or script runtime. */
export function scan(source, {extension = '.mrk', maxBytes = 1048576} = {}) {
  if (typeof source !== 'string') throw new TypeError('source must be text');
  if (Buffer.byteLength(source, 'utf8') > maxBytes) throw new RangeError('document limit');
  const nodes = [], diagnostics = [];
  const emit = (code, line, start, end) => diagnostics.push({code, line, start, end});
  if (extension !== '.mrk') return {source, nodes, diagnostics};
  let offset = 0, fence = null, snippet = null;
  const ids = new Set();
  const lines = source.match(/[^\n]*\n|[^\n]+$/g) ?? [];
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i], text = raw.replace(/\r?\n$/, ''), end = offset + raw.length;
    const loc = {line: i + 1, start: offset, end};
    if (fence) {
      const close = text.match(/^ {0,3}(`{3,}|~{3,})[ \t]*$/);
      if (close && close[1][0] === fence.char && close[1].length >= fence.length) {
        if (fence.node) { fence.node.contentEnd = offset; fence.node.end = end; nodes.push(fence.node); }
        fence = null;
      }
      offset = end; continue;
    }
    const open = text.match(/^ {0,3}(`{3,}|~{3,})(.*)$/);
    if (open && !(open[1][0] === '`' && open[2].includes('`'))) {
      const info = open[2].trim();
      fence = {char: open[1][0], length: open[1].length, node: null};
      if (/^markright-(data|js)(?:\s|$)/.test(info)) {
        const m = info.match(/^(markright-data|markright-js) id="([A-Za-z][A-Za-z0-9_-]*)"(?: inputs="([A-Za-z][A-Za-z0-9_-]*(?:,[A-Za-z][A-Za-z0-9_-]*)*)")?$/);
        if (!m || (m[1] === 'markright-data' && m[3])) emit('invalid-fence-attributes', ...[loc.line, loc.start, loc.end]);
        else {
          if (ids.has(m[2])) emit('duplicate-id', loc.line, loc.start, loc.end);
          ids.add(m[2]);
          fence.node = {type: m[1] === 'markright-data' ? 'data' : 'script', id: m[2], inputs: m[3]?.split(',') ?? [], ...loc, contentStart: end};
        }
      }
      offset = end; continue;
    }
    // Directives are column-zero blocks only. Nested containers and indented code
    // remain owned by the future CommonMark parser, not this spike.
    if (text.startsWith('::include')) {
      const m = text.match(/^::include\{src="([^"\x00-\x1f]+)"(?: headingOffset="([0-5])")?\}[ \t]*$/);
      if (m) nodes.push({type:'include', src:m[1], headingOffset:Number(m[2] ?? 0), ...loc});
      else emit('invalid-include', loc.line, loc.start, loc.end);
    } else if (text.startsWith(':::snippet')) {
      const m = text.match(/^:::snippet\{id="([A-Za-z][A-Za-z0-9_-]*)"\}[ \t]*$/);
      if (!m || snippet) emit('invalid-snippet', loc.line, loc.start, loc.end);
      else {
        if (ids.has(m[1])) emit('duplicate-id', loc.line, loc.start, loc.end);
        ids.add(m[1]); snippet = {type:'snippet', id:m[1], ...loc, contentStart:end};
      }
    } else if (/^:::[ \t]*$/.test(text) && snippet) {
      snippet.contentEnd = offset; snippet.end = end; nodes.push(snippet); snippet = null;
    } else if (/^:{2,}[A-Za-z]/.test(text)) emit('unknown-directive', loc.line, loc.start, loc.end);
    offset = end;
  }
  if (fence?.node) emit('unclosed-extension-fence', fence.node.line, fence.node.start, source.length);
  if (snippet) emit('unclosed-snippet', snippet.line, snippet.start, source.length);
  return {source, nodes: nodes.sort((a,b)=>a.start-b.start), diagnostics};
}
