// Research boundary, not a production IPC transport or renderer.
import { visit } from 'jsonc-parser';
const fail = () => { throw new Error('Unsupported or invalid calculator data'); };
export function strictJSON(source) {
  if (typeof source !== 'string' || Buffer.byteLength(source) > 65536) fail();
  const stack = []; let nodes = 0;
  const count = () => { if (++nodes > 4096) fail(); };
  const begin = (keys) => { count(); stack.push(keys); if (stack.length > 12) fail(); };
  visit(source, {
    onObjectBegin: () => begin(new Set()), onArrayBegin: () => begin(null),
    onObjectEnd: () => stack.pop(), onArrayEnd: () => stack.pop(),
    onObjectProperty: key => { count(); const keys = stack.at(-1); if (!keys || keys.has(key) || ['__proto__','constructor','prototype'].includes(key)) fail(); keys.add(key); },
    onLiteralValue: value => { count(); if ((typeof value === 'string' && value.length > 4096) || (typeof value === 'number' && !Number.isFinite(value))) fail(); },
    onError: fail,
  }, { disallowComments: true, allowTrailingComma: false, allowEmptyContent: false });
  return JSON.parse(source);
}
function exact(value, keys) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || Object.keys(value).some(k => !keys.includes(k)) || keys.some(k => !Object.hasOwn(value,k))) fail();
}
const string = v => { if (typeof v !== 'string' || v.length > 4096) fail(); };
export function validateOutput(source) {
  const value = strictJSON(source);
  exact(value, ['version','kind','columns','rows']);
  if (value.version !== '0.1' || value.kind !== 'table' || !Array.isArray(value.columns) || value.columns.length < 1 || value.columns.length > 8 || !Array.isArray(value.rows) || value.rows.length > 64) fail();
  value.columns.forEach(string);
  for (const row of value.rows) { if (!Array.isArray(row) || row.length !== value.columns.length) fail(); row.forEach(string); }
  // Consumers must render all strings as text, never HTML/Markdown/URLs.
  return value;
}
export function decodeBitfields(source, input) {
  const spec = strictJSON(source);
  exact(spec, ['kind','bits','fields']);
  if (spec.kind !== 'markright.bitfields/0.1' || ![8,16,32,64].includes(spec.bits) || !Array.isArray(spec.fields) || spec.fields.length < 1 || spec.fields.length > 64) fail();
  if (typeof input !== 'string' || input.length > 20 || !/^(?:0|[1-9][0-9]*|0x[0-9a-fA-F]+)$/.test(input)) fail();
  const number = BigInt(input); if (number >= 1n << BigInt(spec.bits)) fail();
  let occupied = 0n; const ids = new Set(); const rows = [];
  for (const field of spec.fields) {
    exact(field, ['id','label','lsb','width','signed']); string(field.label);
    if (typeof field.id !== 'string' || !/^[A-Za-z][A-Za-z0-9_-]{0,63}$/.test(field.id) || ids.has(field.id) || !Number.isInteger(field.lsb) || !Number.isInteger(field.width) || field.lsb < 0 || field.width < 1 || field.lsb + field.width > spec.bits || typeof field.signed !== 'boolean') fail();
    ids.add(field.id);
    const width = BigInt(field.width), mask = (1n << width) - 1n, located = mask << BigInt(field.lsb);
    if (occupied & located) fail(); occupied |= located;
    let decoded = (number >> BigInt(field.lsb)) & mask;
    if (field.signed && (decoded & (1n << (width - 1n)))) decoded -= 1n << width;
    rows.push([field.label, decoded.toString()]);
  }
  return validateOutput(JSON.stringify({version:'0.1',kind:'table',columns:['Field','Value'],rows}));
}
