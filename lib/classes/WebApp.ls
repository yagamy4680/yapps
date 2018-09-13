require! \./BaseApp
{DBG, ERR, WARN, INFO} = global.get-logger __filename

HOOK = (err) ->
  {yap-webapp-start-hook} = global
  yap-webapp-start-hook err if yap-webapp-start-hook?
  return err

class WebApp extends BaseApp
  (@name, @opts, @helpers, @argv) ->
    super ...
    INFO "web-app initiates"
    this.add-plugin require './web'


  init: (done) ->
    self = @
    super (err) ->
      return done err if err?
      {web} = self.context
      return web.start (err) -> return done HOOK err


module.exports = exports = WebApp
