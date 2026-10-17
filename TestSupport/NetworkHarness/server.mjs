// Local synthetic HTTP server only. No credentials or requests leave loopback.
import http from 'node:http';
import {gzipSync} from 'node:zlib';
import {writeFileSync} from 'node:fs';
const stats = {};
const meal = {title:'Synthetic test meal',items:[{id:'test',name:'Test food',portion:'1 portion',nutrition:{calories:200,protein:20,carbs:10,fat:9},confidence:'low',assumptions:[],evidence:[]}],assumptions:[],questions:[]};
const server = http.createServer(async (req,res) => {
  if(req.url==='/stats') {res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(stats));return;}
  if(req.url==='/redirect-target') {stats.redirectHits=(stats.redirectHits??0)+1;res.end('should not be reached');return;}
  let body=''; for await(const chunk of req) body+=chunk;
  const mode=JSON.parse(body).description;
  stats[mode]={chunks:0,closed:false,finished:false}; const stat=stats[mode];
  res.on('close',()=>{stat.closed=true;});
  if(mode==='large-length'||mode==='large-stream') {
    const headers={'Content-Type':'application/json'};
    if(mode==='large-length')headers['Content-Length']=5_000_000;
    res.writeHead(200,headers);res.flushHeaders();
    const timer=setInterval(()=>{stat.chunks++;res.write(Buffer.alloc(50_000,32));if(stat.chunks===100){stat.finished=true;clearInterval(timer);res.end();}},5);
    res.on('close',()=>clearInterval(timer));return;
  }
  if(mode==='redirect') {res.writeHead(307,{Location:'/redirect-target'});res.end();return;}
  if(mode==='exact-size'||mode==='gzip-large') {
    const text=JSON.stringify(meal).padEnd(mode==='exact-size'?250_000:600_000,' ');
    const body=mode==='gzip-large'?gzipSync(text):Buffer.from(text);
    res.writeHead(200,{'Content-Type':'application/json','Content-Length':body.length,...(mode==='gzip-large'?{'Content-Encoding':'gzip'}:{})});res.end(body);stat.finished=true;return;
  }
  if(mode==='cancel'||mode==='timeout') {res.writeHead(200,{'Content-Type':'application/json'});res.flushHeaders();const timer=setInterval(()=>{stat.chunks++;res.write(' ');},10);res.on('close',()=>clearInterval(timer));return;}
  if(mode==='wrong-type') {res.writeHead(200,{'Content-Type':'text/html'});res.end(JSON.stringify(meal));return;}
  if(mode==='invalid-json') {res.writeHead(200,{'Content-Type':'application/json'});res.end('{');return;}
  if(mode==='server-error') {res.writeHead(401,{'Content-Type':'application/json'});res.end(JSON.stringify({error:'Synthetic authorization error'}));return;}
  const result=structuredClone(meal);
  if(mode==='bad-photo')result.items[0].evidence=[{kind:'label',photoNumber:1,detail:'No image was supplied'}];
  res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(result));stat.finished=true;
});
server.listen(0,'127.0.0.1',()=>writeFileSync(process.argv[2],String(server.address().port)));
