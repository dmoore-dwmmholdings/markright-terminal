import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {decodeBitfields} from '../spikes/runtime/output-boundary.mjs';

// Authored, trusted test data. This corpus tests shared calculator semantics;
// it does not make Foundation JSONDecoder an untrusted-document validator.
const fixture = JSON.parse(readFileSync(new URL('../fixtures/bitfields-0.1.json', import.meta.url)));
test('shared native/JavaScript bit-field vectors retain exact integer/text tables', () => {
  assert.equal(fixture.profile, 'markright.bitfields/0.1');
  for (const vector of fixture.cases.filter(value => value.expected)) {
    assert.deepEqual(decodeBitfields(JSON.stringify(vector.spec), vector.input), vector.expected, vector.id);
  }
});
test('shared native/JavaScript bit-field vectors fail closed on unsupported semantics', () => {
  for (const vector of fixture.cases.filter(value => value.reject)) {
    assert.throws(() => decodeBitfields(JSON.stringify(vector.spec), vector.input), undefined, vector.id);
  }
});
