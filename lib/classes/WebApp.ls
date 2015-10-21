require! \./BaseApp
{DBG, ERR, WARN, INFO} = global.get-logger __filename

class WebApp extends BaseApp
  (@name, @opts, @helpers) ->
    super ...
    INFO "web-app initiates"
    this.add-plugin require './web'


  init: (done) ->
    self = @
    super (err) ->
      return done err if err?
      {web} = self.context
      return web.start done


module.exports = exports = WebApp
