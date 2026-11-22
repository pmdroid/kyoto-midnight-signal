const path=require('node:path');
const output=path.resolve(process.argv[2]||'build/hosted-web');
const fs=require('node:fs');const vm=require('node:vm');const crypto=require('node:crypto');const assert=require('node:assert/strict');
(async()=>{
 const manifest=JSON.parse(fs.readFileSync(path.join(output,'engine-integrity.json'),'utf8'));
 const gzip=fs.readFileSync(path.join(output,'index.wasm.gz'));
 const code=fs.readFileSync(path.join(output,'engine-loader.js'),'utf8');
 const requests=[];
 const scope={URL,Request,Response,DecompressionStream,document:{baseURI:'https://example.test/'},fetch:async(url)=>{requests.push(String(url));return new Response(gzip,{status:200})}};
 vm.createContext(scope);vm.runInContext(code,scope);
 const response=await scope.fetch('https://example.test/index.wasm');
 const bytes=Buffer.from(await response.arrayBuffer());
 assert.equal(bytes.length,manifest.uncompressed_bytes);
 assert.equal(crypto.createHash('sha256').update(bytes).digest('hex'),manifest.sha256);
 assert.equal(response.headers.get('content-type'),'application/wasm');
 assert.equal(WebAssembly.validate(bytes),true);
 assert.deepEqual(requests,['https://example.test/index.wasm.gz']);
 await scope.fetch('https://example.test/index.pck');assert(requests.at(-1).endsWith('index.pck'));
 const fail={URL,Request,Response,DecompressionStream,document:{baseURI:'https://example.test/'},fetch:async()=>new Response('Missing',{status:404})};vm.createContext(fail);vm.runInContext(code,fail);await assert.rejects(()=>fail.fetch('index.wasm'),/404/);
 const html=fs.readFileSync(path.join(output,'index.html'),'utf8');assert(html.indexOf('engine-loader.js')<html.indexOf('src="index.js"'));
 for(const file of fs.readdirSync(output)){const p=path.join(output,file);if(fs.statSync(p).isFile())assert(fs.statSync(p).size<25*1024*1024,p+' exceeds limit')}
 console.log('PASS: hosted engine byte identity, valid WebAssembly, MIME, request routing, error handling, loader order and static asset sizes');
})().catch(e=>{console.error(e);process.exit(1)});
