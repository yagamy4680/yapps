require! <[yap-simple-logger path]>

yap-simple-logger.init module.parent.parent.filename

module.exports = exports =
  init: ->
    get-logger-currying = (name, m) --> return yap-simple-logger.get-logger name, m
    pre = (request, parent, isMain) -> return get-logger: get-logger-currying request
    require \yap-require-hook .install pre

