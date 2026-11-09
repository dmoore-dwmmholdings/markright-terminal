import test from 'node:test';
import assert from 'node:assert/strict';
import {history, undo, redo} from '@codemirror/commands';
import {sourceState, sourceText, sourceChange, toEditorOffset, toSourceOffset} from '../spikes/desktop/source-buffer.mjs';

function editor(source) {
  let state = sourceState(source, history());
  return {
    get state() { return state; },
    dispatch: spec => { state = state.update(spec).state; },
    undo() { return undo({state, dispatch: spec => { state = state.update(spec).state; }}); },
    redo() { return redo({state, dispatch: spec => { state = state.update(spec).state; }}); }
  };
}
test('source buffer retains BOM, Unicode and mixed original separators', () => {
  for (const source of ['', '\uFEFF😀\r\ne\u0301\rx\n', 'a\r\n', '\r', '\n\r\n\r']) {
    const state = sourceState(source);
    assert.equal(sourceText(state), source);
    for (let offset = 0; offset <= source.length; offset++) {
      const splitCRLF = source[offset - 1] === '\r' && source[offset] === '\n';
      const splitScalar = /[\uD800-\uDBFF]/.test(source[offset - 1] ?? '') && /[\uDC00-\uDFFF]/.test(source[offset] ?? '');
      if (splitCRLF || splitScalar) assert.throws(() => toEditorOffset(state, offset), RangeError);
      else assert.equal(toSourceOffset(state, toEditorOffset(state, offset)), offset);
    }
  }
});
test('typing preserves untouched separators and newlines use the initial source convention', () => {
  const e = editor('a\r\nb\rc\n');
  e.dispatch({changes: {from: 3, insert: '😀\nX'}, userEvent: 'input.type'});
  assert.equal(sourceText(e.state), 'a\r\nb😀\r\nX\rc\n');
  assert.equal(e.undo(), true); assert.equal(sourceText(e.state), 'a\r\nb\rc\n');
  assert.equal(e.redo(), true); assert.equal(sourceText(e.state), 'a\r\nb😀\r\nX\rc\n');
});
test('raw replacements and grouped undo/redo restore every deleted separator exactly', () => {
  const initial = 'one\r\ntwo\rthree\nfour\r\n';
  const e = editor(initial);
  e.dispatch(sourceChange(e.state, 2, 10, 'A\nB\r\nC\r', 'input.type'));
  const middle = sourceText(e.state);
  e.dispatch(sourceChange(e.state, 3, 5, '\r\nQ\n', 'input.type'));
  const final = sourceText(e.state);
  assert.notEqual(final, initial); assert.notEqual(final, middle);
  assert.equal(e.undo(), true); assert.equal(sourceText(e.state), initial);
  assert.equal(e.redo(), true); assert.equal(sourceText(e.state), final);
});
test('deleting exactly at a newline never restores its ending onto the next newline', () => {
  const e = editor('a\r\nb\rc\n');
  e.dispatch({changes: {from: 1, to: 2}, userEvent: 'delete.forward'});
  e.dispatch({changes: {from: 1, to: 3}, userEvent: 'delete.forward'});
  assert.equal(sourceText(e.state), 'ac\n');
  assert.equal(e.undo(), true); assert.equal(sourceText(e.state), 'a\r\nb\rc\n');
  assert.equal(e.redo(), true); assert.equal(sourceText(e.state), 'ac\n');
});
test('simultaneous edits preserve untouched mixed separators and invert independently', () => {
  const e = editor('a\r\nb\rc\nd');
  e.dispatch({changes: [{from: 0, to: 1, insert: 'A'}, {from: 4, to: 6, insert: 'C\nD\n'}]});
  assert.equal(sourceText(e.state), 'A\r\nb\rC\r\nD\r\nd');
  assert.equal(e.undo(), true); assert.equal(sourceText(e.state), 'a\r\nb\rc\nd');
});
test('offset conversions refuse invalid, surrogate-splitting and reversed edits', () => {
  const state = sourceState('😀\r\nx');
  for (const offset of [-1, 1, 1.5, 7]) assert.throws(() => toSourceOffset(state, offset), RangeError);
  assert.throws(() => sourceChange(state, 3, 2, 'x'), RangeError);
});
test('edits that join CR and LF keep source, editor lines and undo consistent', () => {
  for (const [initial, change] of [
    ['a\rX\nb', state => ({changes: {from: 2, to: 3}})],
    ['a\rb', state => sourceChange(state, 2, 2, '\n')],
    ['a\nb', state => sourceChange(state, 1, 1, '\r')],
    ['a\rX\nb\rY\nc', state => ({changes: [{from: 2, to: 3}, {from: 6, to: 7}]})]
  ]) {
    const e = editor(initial);
    e.dispatch(change(e.state));
    const changed = sourceText(e.state);
    assert.equal(changed, initial.includes('Y') ? 'a\r\nb\r\nc' : 'a\r\nb');
    assert.equal(e.state.doc.toString(), changed.replace(/\r\n|\r/g, '\n'));
    assert.throws(() => toEditorOffset(e.state, 2), /CRLF/);
    assert.equal(e.undo(), true); assert.equal(sourceText(e.state), initial);
    assert.equal(e.redo(), true); assert.equal(sourceText(e.state), changed);
  }
});
test('deterministic raw-edit sequences match authoritative source splices and exact undo/redo', () => {
  let seed = 0x4d524b;
  const random = () => (seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0);
  const parts = ['x', '\r', '\n', '\r\n', '😀', 'e\u0301', ''];
  const e = editor('\uFEFFstart\r\nnext\rlast\n');
  for (let iteration = 0; iteration < 200; iteration++) {
    const before = sourceText(e.state), boundaries = [];
    for (let offset = 0; offset <= before.length; offset++) {
      try { toEditorOffset(e.state, offset); boundaries.push(offset); } catch { /* CRLF/scalar interior */ }
    }
    const a = boundaries[random() % boundaries.length], b = boundaries[random() % boundaries.length];
    const from = Math.min(a, b), to = Math.max(a, b), insert = parts[random() % parts.length] + parts[random() % parts.length];
    const expected = before.slice(0, from) + insert + before.slice(to);
    e.dispatch(sourceChange(e.state, toEditorOffset(e.state, from), toEditorOffset(e.state, to), insert));
    assert.equal(sourceText(e.state), expected, `edit ${iteration}`);
    assert.equal(e.state.doc.toString(), expected.replace(/\r\n|\r/g, '\n'));
    if (expected !== before) {
      assert.equal(e.undo(), true); assert.equal(sourceText(e.state), before, `undo ${iteration}`);
      assert.equal(e.redo(), true); assert.equal(sourceText(e.state), expected, `redo ${iteration}`);
    }
  }
});
test('newline-dense source updates without spread-argument overflow', () => {
  const state = sourceState('\r\n'.repeat(150000));
  const next = state.update({changes: {from: 1, insert: 'X'}}).state;
  assert.equal(sourceText(next), '\r\nX' + '\r\n'.repeat(149999));
});
