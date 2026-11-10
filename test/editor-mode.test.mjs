import test from 'node:test';
import assert from 'node:assert/strict';
import {Compartment} from '@codemirror/state';
import {EditorView} from '@codemirror/view';
import {history,undo,redo} from '@codemirror/commands';
import {editorModeExtensions} from '../spikes/desktop/editor-mode.mjs';
import {sourceState,sourceText,sourceChange,toEditorOffset,toSourceOffset} from '../spikes/desktop/source-buffer.mjs';

function editor(source) {
  const mode = new Compartment();
  let state = sourceState(source,[history(),mode.of(editorModeExtensions('live',[]))]);
  const view = {get state(){return state;},dispatch:spec=>{state=state.update(spec).state;}};
  return {...view,get state(){return state;},
    mode:value=>view.dispatch({effects:mode.reconfigure(editorModeExtensions(value,[]))}),
    undo:()=>undo(view),redo:()=>redo(view)};
}

test('reading state rejects edits while mode changes retain exact source and reverse selection',()=>{
  const source='\uFEFFfirst\r\nA **bold** line\rafter\n',e=editor(source);
  e.dispatch({selection:{anchor:toEditorOffset(e.state,source.indexOf('bold')+3),head:toEditorOffset(e.state,source.indexOf('bold'))}});
  const selected=e.state.selection;
  for(const mode of ['source','reading','live','reading','source']){
    e.mode(mode);
    assert.equal(e.state.readOnly,mode==='reading');
    assert.equal(e.state.facet(EditorView.editable),mode!=='reading');
    assert.equal(sourceText(e.state),source);
    assert.ok(e.state.selection.eq(selected));
    if(mode==='reading'){
      e.dispatch(sourceChange(e.state,0,e.state.doc.length,'REPLACED\r\n'));
      e.dispatch({changes:{from:0,insert:'NO'}});
      assert.equal(sourceText(e.state),source);
      assert.ok(e.state.selection.eq(selected));
    }
  }
  assert.equal(toSourceOffset(e.state,e.state.selection.main.head),source.indexOf('bold'));
});

test('reading mode refuses history commands without consuming undo or redo entries',()=>{
  const source='a\r\nb\rc\n',e=editor(source);
  e.dispatch(sourceChange(e.state,1,3,'😀\nX'));
  const edited=sourceText(e.state);
  e.mode('reading');assert.equal(e.undo(),false);assert.equal(sourceText(e.state),edited);
  e.mode('source');assert.equal(e.undo(),true);assert.equal(sourceText(e.state),source);
  e.mode('reading');assert.equal(e.redo(),false);assert.equal(sourceText(e.state),source);
  e.mode('live');assert.equal(e.redo(),true);assert.equal(sourceText(e.state),edited);
});

test('mode configuration refuses unknown modes',()=>{
  for(const mode of ['',null,undefined,'Reading','unknown'])assert.throws(()=>editorModeExtensions(mode,[]),RangeError);
});
