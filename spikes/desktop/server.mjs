import http from 'node:http';import fs from 'node:fs';
const files={'/':['./index.html','text/html'],'/bundle.js':['./build/bundle.js','text/javascript']};
const server=http.createServer((req,res)=>{const file=files[new URL(req.url,'http://127.0.0.1').pathname];if(!file){res.writeHead(404).end();return;}res.setHeader('Content-Type',file[1]);res.setHeader('Cache-Control','no-store');res.end(fs.readFileSync(new URL(file[0],import.meta.url)));});
const port=Number(process.env.MARKRIGHT_PREVIEW_PORT??18790);
if(!Number.isInteger(port)||port<1024||port>65535)throw new RangeError('Invalid preview port');
server.listen(port,'127.0.0.1');
