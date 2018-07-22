require \source-map-support .install!
require \yap-require-hook .install!
require \./helpers/gm

logger = require \yap-simple-logger
inner = require \./inner


STR_STARTS_WITH = (str) -> return 0 is this.index-of str
STR_ENDS_WITH = (str) -> return str is this.substring this.length - str.length, this.length

String.prototype.starts-with = STR_STARTS_WITH unless String.prototype.starts-with?
String.prototype.ends-with = STR_ENDS_WITH unless String.prototype.ends-with?

module.exports = exports =
  init: (app_filename) ->
    logger.init app_filename, __filename
    inner.init app_filename

  create-app: (type, opts) ->
    return inner.create-app type, opts
