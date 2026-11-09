/** Proposed format dispatch. A marker never opts a .md file into extensions. */
export function formatProfile(source,extension='.mrk') {
 if(extension!=='.mrk')return {enabled:false,version:null,diagnostics:[]};
 const first=source.split(/\r\n|\r|\n/,1)[0];
 const line=first.replace(/^\uFEFF/,'');
 if(!line.startsWith('<!-- markright:'))return {enabled:true,version:'0.1',diagnostics:[]};
 const marker=line.match(/^<!-- markright: ([0-9]+\.[0-9]+) -->$/);
 if(marker?.[1]==='0.1')return {enabled:true,version:'0.1',diagnostics:[]};
 return {enabled:false,version:null,diagnostics:[{code:marker?'unsupported-format-version':'invalid-format-marker',line:1,start:0,end:first.length}]};
}
