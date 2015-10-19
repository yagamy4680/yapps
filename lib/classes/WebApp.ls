require! \./BaseApp
require! <[express]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename

class WebApp extends BaseApp
  (@name, @opts, @helpers) ->
    super ...
    INFO "web-app initiates"

module.exports = exports = WebApp
