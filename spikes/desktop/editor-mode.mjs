import {EditorState} from '@codemirror/state';
import {EditorView} from '@codemirror/view';

// UI editing policy, not a sandbox boundary. A trusted host can replace state
// or explicitly bypass transaction filters; document source has no such API.
export function editorModeExtensions(mode, projection) {
  if (!['live', 'source', 'reading'].includes(mode)) throw new RangeError('Unknown editor mode');
  return [
    mode === 'source' ? [] : projection,
    EditorState.readOnly.of(mode === 'reading'),
    EditorView.editable.of(mode !== 'reading'),
    EditorState.transactionFilter.of(transaction =>
      transaction.startState.readOnly && transaction.docChanged ? [] : transaction)
  ];
}
