import {mkdir, readFile, writeFile, copyFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {resolve, dirname} from 'node:path';
import {createHash} from 'node:crypto';

// Copy only the authored synthetic editor and its already-built, pinned bundle.
// Run the desktop esbuild command first; this script fetches nothing.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const desktop = resolve(root, 'spikes/desktop');
const output = resolve(root, 'spikes/macos-editor/Resources/Editor');
const html = await readFile(resolve(desktop, 'index.html'), 'utf8');
const bundle = await readFile(resolve(desktop, 'build/bundle.js'));
const originalScript = '<script type="module" src="/bundle.js"></script>';
if (!html.includes('<meta charset="utf-8">') || !html.includes(originalScript)) {
  throw new Error('Desktop fixture structure changed; review the host resource adapter.');
}
if (!bundle.toString('utf8').startsWith('(() => {')) {
  throw new Error('Expected an esbuild IIFE bundle without external module loading.');
}
const policy = [
  "default-src 'none'", "script-src 'self'", "style-src 'unsafe-inline'",
  "connect-src 'none'", "img-src 'none'", "font-src 'none'", "media-src 'none'",
  "object-src 'none'", "frame-src 'none'", "child-src 'none'", "worker-src 'none'",
  "base-uri 'none'", "form-action 'none'", "manifest-src 'none'"
].join('; ');
const adapted = html
  .replace('<meta charset="utf-8">', `<meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="${policy}">`)
  .replace(originalScript, '<script src="./bundle.js"></script>');
await mkdir(output, {recursive: true});
await writeFile(resolve(output, 'index.html'), adapted);
await copyFile(resolve(desktop, 'build/bundle.js'), resolve(output, 'bundle.js'));
console.log(`Prepared synthetic WKWebView resources; bundle SHA-256 ${createHash('sha256').update(bundle).digest('hex')}`);
