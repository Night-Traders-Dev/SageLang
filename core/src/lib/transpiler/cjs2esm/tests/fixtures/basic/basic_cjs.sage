// Basic CJS test file
const http = require("http");
const path = require("path");

function handler(req, res) {
  res.writeHead(200, {"Content-Type": "text/plain"});
  res.end("Hello World\\n");
}

module.exports = { handler };