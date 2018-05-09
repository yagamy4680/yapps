require \source-map-support .install!
require \yap-require-hook .install!
require \./helpers/gm

STR_STARTS_WITH = (str) -> return 0 is this.index-of str
STR_ENDS_WITH = (str) -> return str is this.substring this.length - str.length, this.length

String.prototype.starts-with = STR_STARTS_WITH unless String.prototype.starts-with?
String.prototype.ends-with = STR_ENDS_WITH unless String.prototype.ends-with?

module.exports = exports =
  init: (app_filename) ->
    require \yap-simple-logger .init app_filename, __filename
    require \./inner .init app_filename

  create-app: (type, opts) ->
    app = require \./inner .create-app type, opts
    signal = require \./helpers/signal
    return signal app
