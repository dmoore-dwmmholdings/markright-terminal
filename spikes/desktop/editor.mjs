import {StateEffect} from '@codemirror/state';
import {EditorView,Decoration,ViewPlugin,keymap} from '@codemirror/view';
import {markdown} from '@codemirror/lang-markdown';
import {syntaxTree} from '@codemirror/language';
import {history,historyKeymap,defaultKeymap} from '@codemirror/commands';
import {GFM} from '@lezer/markdown';
import {sourceState,sourceText,sourceChange,toEditorOffset,toSourceOffset} from './source-buffer.mjs';
const refresh=StateEffect.define();
function activeSource(view){
 const selection=view.state.selection.main;
 let from=view.state.doc.lineAt(selection.from).from,to=view.state.doc.lineAt(selection.to>selection.from?selection.to-1:selection.to).to;
  for(const position of [selection.from,selection.to>selection.from?selection.to-1:selection.to]){
  for(const side of [-1,1]){
   let node=syntaxTree(view.state).resolveInner(position,side);
   for(;node;node=node.parent){
    // An unclosed fence owns the empty EOF line where its next body edit occurs.
    // Closed fences end before that line; their second CodeMark also distinguishes them.
    const openFenceEOF=position===view.state.doc.length&&position===node.to&&node.name==='FencedCode'&&node.getChildren('CodeMark').length===1;
    const inside=position<node.to||(position===node.to&&view.state.doc.lineAt(position).from<position)||openFenceEOF;
    if(inside&&['FencedCode','CodeBlock','Table'].includes(node.name)){from=Math.min(from,node.from);to=Math.max(to,node.to);}
   }
  }
 }
 return {from,to};
}
function decorations(view){
 const active=activeSource(view),ranges=[];
 const overlap=(a,b)=>a<=active.to&&b>=active.from;
 syntaxTree(view.state).iterate({enter(node){
  if(overlap(node.from,node.to))return;
  if(['HeaderMark','EmphasisMark','StrikethroughMark','CodeMark','CodeInfo'].includes(node.name)){
   if(node.from<node.to)ranges.push(Decoration.replace({}).range(node.from,node.to));
  }else if(['StrongEmphasis','Emphasis','Strikethrough','ATXHeading1','ATXHeading2'].includes(node.name)){
   ranges.push(Decoration.mark({class:'preview-'+node.name}).range(node.from,node.to));
  }
 }});
 return Decoration.set(ranges,true);
}
const projection=ViewPlugin.fromClass(class{
 constructor(view){this.decorations=decorations(view);}
 update(update){
  if(update.view.composing){this.decorations=this.decorations.map(update.changes);return;}
  if(update.docChanged||update.selectionSet||update.viewportChanged||syntaxTree(update.startState)!==syntaxTree(update.state)||update.transactions.some(t=>t.effects.some(e=>e.is(refresh))))this.decorations=decorations(update.view);
 }
},{decorations:value=>value.decorations});
const sample='# Markright Terminal\n\nA **bold** preview with *emphasis* and ~~removed~~ text.\n\n```js\nconst register = 42;\n```\n\n| Field | Value |\n| --- | --- |\n| status | ready |\n';
function createState(source){return sourceState(source,[history(),keymap.of([...defaultKeymap,...historyKeymap]),markdown({extensions:GFM}),projection,EditorView.lineWrapping,EditorView.contentAttributes.of({'aria-label':'Markright source editor',spellcheck:'false',autocorrect:'off',autocapitalize:'off'}),EditorView.domEventHandlers({
 compositionend(){setTimeout(()=>view.dispatch({effects:refresh.of(null)}),0);return false;},
 paste(event,view){
  if(!event.clipboardData||!Array.from(event.clipboardData.types).includes('text/plain')||view.state.selection.ranges.length!==1)return false;
  const selection=view.state.selection.main;
  view.dispatch(sourceChange(view.state,selection.from,selection.to,event.clipboardData.getData('text/plain')));
  event.preventDefault();return true;
 }
})]);}
const view=new EditorView({parent:document.querySelector('#editor'),state:createState(sample)});
// Test-only local harness. No document code is evaluated and no files are accessed.
window.spike={source:()=>sourceText(view.state),select:(from,to=from)=>view.dispatch({selection:{anchor:toEditorOffset(view.state,from),head:toEditorOffset(view.state,to)},scrollIntoView:true}),setSource:source=>view.setState(createState(source)),active:()=>{const range=activeSource(view);return {from:toSourceOffset(view.state,range.from),to:toSourceOffset(view.state,range.to)};},focus:()=>view.focus()};
