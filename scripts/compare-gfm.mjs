import fs from 'node:fs';
import {micromark} from 'micromark';
import {gfm,gfmHtml} from 'micromark-extension-gfm';
const cases=JSON.parse(fs.readFileSync(new URL('../fixtures/gfm-0.29.json',import.meta.url)));
const failures=[];
for(const c of cases){
 const actual=micromark(c.markdown,{extensions:[gfm()],htmlExtensions:[gfmHtml()],allowDangerousHtml:true,allowDangerousProtocol:true});
 if(actual!==c.html){failures.push(c.example);if(process.argv.includes('--diffs'))console.log(JSON.stringify({...c,actual}));}
}
console.log(JSON.stringify({parser:'micromark-gfm',total:cases.length,exact:cases.length-failures.length,failures}));
