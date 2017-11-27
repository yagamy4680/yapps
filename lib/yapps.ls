require \source-map-support .install!
require \yap-require-hook .install!
require \./gm

if not String.prototype.starts-with?
  String.prototype.starts-with = (search-string) -> return 0 == this.index-of search-string

if not String.prototype.ends-with?
  String.prototype.ends-with = (str) -> return str == this.substring this.length - str.length, this.length

module.exports = exports =
  init: (app-filename) ->
    require \yap-simple-logger .init app-filename, __filename
    require \./inner .init app-filename

  create-app: (type, opts) ->
    require \./inner .create-app type, opts
