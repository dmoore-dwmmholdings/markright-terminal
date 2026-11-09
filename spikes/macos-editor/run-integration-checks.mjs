import {mkdir, readFile, writeFile, copyFile, stat} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

const directory = dirname(fileURLToPath(import.meta.url));
const root = resolve(directory, '../..');
const build = resolve(directory, 'build');
const app = resolve(build, 'IntegrationChecks.app/Contents');
const control = resolve(build, 'IntegrationControl/Editor');
const fixture = resolve(directory, 'Resources/Editor');
const executable = resolve(app, 'MacOS/IntegrationChecks');
const run = (command, args, timeout = 180000) => new Promise((done, reject) => {
  const child = spawn(command, args, {cwd: root, stdio: 'inherit', timeout, killSignal: 'SIGTERM'});
  child.on('error', reject);
  child.on('exit', (code, signal) => code === 0 ? done() : reject(new Error(`${command} ended with ${signal ?? code}`)));
});

// Keep the build bounded and fail before compilation when shared headroom is low.
const {statfs} = await import('node:fs/promises');
const requireHeadroom = async () => {
  const disk = await statfs(root, {bigint: true});
  if (disk.bavail * disk.bsize < 20n * 1024n ** 3n) throw new Error('Below 20 GiB free; no further build/probe process started.');
};
await requireHeadroom();
await run(process.execPath, [resolve(root, 'node_modules/esbuild/bin/esbuild'), resolve(root, 'spikes/desktop/editor.mjs'), '--bundle', `--outfile=${resolve(root, 'spikes/desktop/build/bundle.js')}`]);
await run(process.execPath, [resolve(directory, 'prepare-resources.mjs')]);
const html = await readFile(resolve(fixture, 'index.html'), 'utf8');
if (!html.includes("connect-src 'none'")) throw new Error('Production CSP changed; review the positive control.');
await mkdir(control, {recursive: true});
await writeFile(resolve(control, 'index.html'), html.replace("connect-src 'none'", 'connect-src http://127.0.0.1:*'));
await copyFile(resolve(fixture, 'bundle.js'), resolve(control, 'bundle.js'));
await mkdir(resolve(app, 'MacOS'), {recursive: true});
await writeFile(resolve(app, 'Info.plist'), `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>com.dwmm.markright.spike.offscreen-checks</string><key>CFBundleExecutable</key><string>IntegrationChecks</string><key>CFBundlePackageType</key><string>APPL</string><key>LSUIElement</key><true/></dict></plist>`);
await requireHeadroom();
await run('/usr/bin/xcrun', ['swiftc', '-swift-version', '6', '-warnings-as-errors', '-parse-as-library',
  '-module-cache-path', resolve(build, 'IntegrationModuleCache'),
  resolve(directory, 'Sources/BundledNavigationPolicy.swift'),
  resolve(directory, 'Sources/BundledEditorController.swift'),
  resolve(directory, 'IntegrationChecks/main.swift'), '-o', executable]);
const binary = await stat(executable);
if (binary.size > 20 * 1024 * 1024) throw new Error('Unexpectedly large probe executable; not launched.');
await requireHeadroom();
await run(executable, [resolve(fixture, 'index.html'), resolve(control, 'index.html')], 45000);
