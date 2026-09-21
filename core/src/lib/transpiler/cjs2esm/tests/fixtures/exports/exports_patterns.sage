// Exports test file - tests various export patterns
const http = require("http");

// Aliased export
const exp = module.exports;
exp.run = function() { console.log("running"); };
exports.version = "1.0.0";

// Later reassignment (should be preserved as compat shim)
module.exports = function main() {
  return "main module";
};

console.log("exports test");