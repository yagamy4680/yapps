require \source-map-support .install!
require \yap-require-hook .install!
require \./helpers/gm

if not String.prototype.starts-with?
  String.prototype.starts-with = (search-string) -> return 0 == this.index-of search-string

if not String.prototype.ends-with?
  String.prototype.ends-with = (str) -> return str == this.substring this.length - str.length, this.length

module.exports = exports =
  init: (app_filename) ->
    require \yap-simple-logger .init app_filename, __filename
    require \./inner .init app_filename

  create-app: (type, opts) ->
    app = require \./inner .create-app type, opts
    signal = require \./helpers/signal
    return signal app
