/**
 * For legacy nodejs runtime, e.g. 0.10.40, that has no
 * startsWith() and endsWith() methods of String object.
 */
if (String.prototype.startsWith == null) {
    String.prototype.startsWith = function(str) { return 0 === this.indexOf(str); };
}
if (String.prototype.endsWith == null) {
    String.prototype.endsWith = function(str) { return str === this.substring(this.length - str.length, this.length); };
}

module.exports = exports = require("./lib/yapps");
