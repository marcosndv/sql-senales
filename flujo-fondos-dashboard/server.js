const http = require('http');
const fs   = require('fs');
const path = require('path');
const dir  = __dirname;
const mime = { '.html':'text/html', '.json':'application/json', '.js':'text/javascript', '.css':'text/css' };
http.createServer((req, res) => {
  const f = path.join(dir, req.url === '/' ? 'index.html' : req.url.split('?')[0]);
  fs.readFile(f, (err, data) => {
    if (err) { res.writeHead(404); res.end('Not found'); return; }
    res.writeHead(200, { 'Content-Type': mime[path.extname(f)] || 'text/plain' });
    res.end(data);
  });
}).listen(8089, '127.0.0.1', () => console.log('Flujo de fondos: http://localhost:8089'));
