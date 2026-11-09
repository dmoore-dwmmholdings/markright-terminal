import {EditorState, StateEffect, StateField, MapMode} from '@codemirror/state';
import {invertedEffects} from '@codemirror/commands';

// Research adapter: CodeMirror positions count one unit per newline. Keep each
// original separator beside that normalized Text, never reconstruct it by policy.
function splitSource(source) {
  const separators = [];
  const text = source.replace(/\r\n|\r|\n/g, separator => {
    separators.push(separator);
    return '\n';
  });
  return {text, separators};
}
function metadata(separators, preferred) {
  const extra = [0];
  for (const separator of separators) extra.push(extra.at(-1) + separator.length - 1);
  return {separators, preferred, extra};
}
const restoreSeparator = StateEffect.define({
  map(value, changes) {
    // The marker describes the newline character AFTER this position. TrackDel
    // would retain a marker when a deletion starts exactly on its newline.
    const position = changes.mapPos(value.position, 1, MapMode.TrackAfter);
    return position == null ? undefined : {...value, position};
  }
});
const sourceMetadata = StateField.define({
  create: () => metadata([], '\n'),
  update(value, transaction) {
    if (!transaction.docChanged && !transaction.effects.some(effect => effect.is(restoreSeparator))) return value;
    const separators = [];
    let copied = 0;
    transaction.changes.iterChanges((from, to, _fromNew, _toNew, inserted) => {
      const first = transaction.startState.doc.lineAt(from).number - 1;
      const last = transaction.startState.doc.lineAt(to).number - 1;
      for (let index = copied; index < first; index++) separators.push(value.separators[index]);
      for (let i = 1; i < inserted.lines; i++) separators.push(value.preferred);
      copied = last;
    });
    for (let index = copied; index < value.separators.length; index++) separators.push(value.separators[index]);
    for (const effect of transaction.effects) if (effect.is(restoreSeparator)) {
      const {position, separator} = effect.value;
      if (position < 0 || position >= transaction.newDoc.length) continue;
      const line = transaction.newDoc.lineAt(position);
      if (position === line.to) separators[line.number - 1] = separator;
    }
    if (separators.length !== transaction.newDoc.lines - 1) throw new Error('Source separator count mismatch');
    return metadata(separators, value.preferred);
  }
});
const sourceHistory = invertedEffects.of(transaction => {
  const effects = [], old = transaction.startState;
  transaction.changes.iterChanges((from, to) => {
    const first = old.doc.lineAt(from).number, last = old.doc.lineAt(to).number;
    for (let number = first; number < last; number++) effects.push(restoreSeparator.of({
      position: old.doc.line(number).to,
      separator: old.field(sourceMetadata).separators[number - 1]
    }));
  });
  // Canonicalizing adjacent CR + LF also changes the surviving separator.
  // Restore its old value even though that newline was not deleted.
  for (const effect of transaction.effects) if (effect.is(restoreSeparator)) {
    const position = transaction.changes.invertedDesc.mapPos(effect.value.position, 1, MapMode.TrackAfter);
    if (position == null || position >= old.doc.length) continue;
    const line = old.doc.lineAt(position);
    if (position === line.to) effects.push(restoreSeparator.of({position, separator: old.field(sourceMetadata).separators[line.number - 1]}));
  }
  return effects;
});
const canonicalBoundaries = EditorState.transactionFilter.of(transaction => {
  if (!transaction.docChanged) return transaction;
  const state = transaction.state, {separators} = state.field(sourceMetadata), corrections = [], starts = [];
  // Removing the text between a CR and an LF joins them into one physical CRLF.
  // Keep editor line boundaries canonical as well as preserving the raw bytes.
  for (let index = 0; index + 1 < separators.length; index++) {
    if (separators[index] === '\r' && separators[index + 1] === '\n' && state.doc.line(index + 2).length === 0) {
      const position = state.doc.line(index + 1).to;
      corrections.push({from: position + 1, to: position + 2});
      starts.push(position);
    }
  }
  if (!corrections.length) return transaction;
  const changes = state.changes(corrections);
  return [transaction, {changes, sequential: true,
    effects: starts.map(position => restoreSeparator.of({position: changes.mapPos(position, 1), separator: '\r\n'}))}];
});

export function sourceState(source, extensions = []) {
  const {text, separators} = splitSource(source);
  return EditorState.create({doc: text, extensions: [
    sourceMetadata.init(() => metadata(separators, separators[0] ?? '\n')),
    sourceHistory, canonicalBoundaries, ...extensions
  ]});
}
export function sourceText(state) {
  const {separators} = state.field(sourceMetadata), result = [];
  for (let number = 1; number <= state.doc.lines; number++) {
    result.push(state.doc.line(number).text);
    if (number < state.doc.lines) result.push(separators[number - 1]);
  }
  return result.join('');
}
function validatePosition(state, position) {
  if (!Number.isInteger(position) || position < 0 || position > state.doc.length) throw new RangeError('Invalid editor offset');
  if (position > 0 && position < state.doc.length && /^[\uD800-\uDBFF][\uDC00-\uDFFF]$/.test(state.doc.sliceString(position - 1, position + 1))) throw new RangeError('Offset splits a surrogate pair');
}
export function toSourceOffset(state, position) {
  validatePosition(state, position);
  return position + state.field(sourceMetadata).extra[state.doc.lineAt(position).number - 1];
}
export function toEditorOffset(state, position) {
  const {extra} = state.field(sourceMetadata);
  if (!Number.isInteger(position) || position < 0 || position > state.doc.length + extra.at(-1)) throw new RangeError('Invalid source offset');
  let low = 1, high = state.doc.lines + 1;
  while (low < high) {
    const middle = (low + high) >>> 1;
    if (state.doc.line(middle).from + extra[middle - 1] <= position) low = middle + 1;
    else high = middle;
  }
  const number = low - 1, line = state.doc.line(number), normalized = position - extra[number - 1];
  if (normalized > line.to) throw new RangeError('Offset splits CRLF');
  validatePosition(state, normalized);
  return normalized;
}

// from/to are normalized editor offsets; an explicit insertion preserves the
// exact separators delivered to this helper. Native keyboard newlines instead
// use the first original separator (LF for an initially newline-free document).
export function sourceChange(state, from, to, insert, userEvent = 'input.paste') {
  validatePosition(state, from); validatePosition(state, to);
  if (from > to) throw new RangeError('Reversed source edit');
  const {text, separators} = splitSource(insert), effects = [];
  let index = 0;
  for (let position = 0; position < text.length; position++) if (text[position] === '\n') {
    effects.push(restoreSeparator.of({position: from + position, separator: separators[index++]}));
  }
  return {changes: {from, to, insert: text}, effects,
    selection: {anchor: from + text.length}, userEvent, scrollIntoView: true};
}
