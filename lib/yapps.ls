require \source-map-support .install!
require \yap-require-hook .install!
require \./helpers/gm
logger = require \yap-simple-logger
inner = require \./inner

module.exports = exports =
  init: (app_filename) ->
    logger.init app_filename, __filename
    inner.init app_filename

  create-app: (type, opts) ->
    return inner.create-app type, opts
