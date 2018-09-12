require \source-map-support .install!
require \yap-require-hook .install!
require \./helpers/gm

module.exports = exports =
  init: (app_filename) ->
    logger = require \./logger
    logger.init app_filename, __filename
    inner = module.inner = require \./inner
    inner.init app_filename

  create-app: (type, opts) ->
    return module.inner.create-app type, opts
