const http = require('http');

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
  res.end('<h1>Termode Real Node.js V8 Server</h1><p>Running natively on Samsung Galaxy Tab S9 FE at port 3000!</p>');
});

server.listen(3000, '0.0.0.0', () => {
  console.log('REAL NODE.JS V8 SERVER IS LISTENING ON http://localhost:3000');
});
