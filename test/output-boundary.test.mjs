import test from 'node:test';
import assert from 'node:assert/strict';
import { strictJSON, validateOutput, decodeBitfields } from '../spikes/runtime/output-boundary.mjs';
const field = {id:'value',label:'Value',lsb:0,width:64,signed:false};
const spec = f => JSON.stringify({kind:'markright.bitfields/0.1',bits:64,fields:f});
test('JSON boundary rejects ambiguous, excessive and malformed data', () => {
  for (const source of ['{"a":1,"a":2}', '{"__proto__":{}}', '{"a":1,}', '{/*x*/"a":1}', '1e999', '[', 'null null', '['.repeat(13)+'0'+']'.repeat(13), JSON.stringify('x'.repeat(4097)), ' '.repeat(65537), JSON.stringify(Array(4097).fill(0))]) assert.throws(()=>strictJSON(source));
});
test('table boundary accepts only inert text cells and explicit version', () => {
  const value = {version:'0.1',kind:'table',columns:['x'],rows:[['<script>alert(1)</script>']]};
  assert.deepEqual(validateOutput(JSON.stringify(value)),value);
  for (const changed of [{...value,html:'x'},{...value,version:'2'}, {...value,rows:[[{url:'https://example.com'}]]}, {...value,rows:[['x','y']]}, {...value,rows:Array(65).fill(['x'])}]) assert.throws(()=>validateOutput(JSON.stringify(changed)));
});
test('declarative decoder preserves unsigned and signed 64-bit precision', () => {
  assert.equal(decodeBitfields(spec([field]),'18446744073709551615').rows[0][1],'18446744073709551615');
  assert.equal(decodeBitfields(spec([{...field,signed:true}]),'0xffffffffffffffff').rows[0][1],'-1');
  assert.equal(decodeBitfields(spec([{...field,width:4,lsb:4}]),'0xA0').rows[0][1],'10');
});
test('declarative decoder refuses unknown operations, overlaps and bad inputs', () => {
  for (const fields of [[field,{...field,id:'other'}],[{...field,width:65}],[{...field,lsb:-1}],[{...field,signed:'yes'}],[{...field,eval:'process.exit()'}]]) assert.throws(()=>decodeBitfields(spec(fields),'1'));
  for (const input of ['-1','1.5','01','0x','18446744073709551616','1+2']) assert.throws(()=>decodeBitfields(spec([field]),input));
  assert.throws(()=>decodeBitfields('{"kind":"download-script","bits":64,"fields":[]}','0'));
});
