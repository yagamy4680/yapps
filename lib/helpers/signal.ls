##
# Inspired by these documents and codes:
#   - https://github.com/tapjs/signal-exit/blob/master/signals.js
#   - ...
#
const SIGNALS = <[SIGABRT SIGALRM SIGHUP SIGINT SIGTERM]>
const SUICIDE_TIMEOUT = 10s    # How long to wait before giving up on graceful shutdown
{DBG, INFO, WARN, ERR} = global.get-logger __filename


class SuicideTimer
  (@evt, @seconds) ->
    self = @
    f = -> return self.at-check!
    self.interval = setInterval f, 1000ms

  at-check: ->
    {evt, seconds, interval} = self = @
    self.seconds = seconds - 1
    text = "#{self.seconds}"
    return INFO "#{evt.red}: peaceful shutdown remains #{text.cyan} seconds ..." if self.seconds > 0
    ERR "#{evt.red}: peaceful shutdown but timeout"
    clearInterval interval
    return process.exit 2


SIGNAL_HANDLER_CURRYING = (evt, dummy) -->
  {app, shutdowning, suicide_timeout} = module
  return WARN "receive #{evt.red} event but already shutdowning ..." if shutdowning
  module.shutdowning = yes
  module.timer = new SuicideTimer evt, suicide_timeout
  WARN "receive #{evt.red} event, peacefully shutdown ..."
  try
    (err, code) <- app.shutdown evt
    ERR err, "peaceful shutdown for signal #{evt.red} event but known error" if err?
    return process.exit 230 if evt is 'SIGTERM' and code is 0
    code = 0 unless code?
    code = 0 unless \number is typeof code
    return process.exit code
  catch error
    ERR error, "peaceful shutdown for signal #{evt.red} event but uncaught error"
    return process.exit 1


module.exports = exports = (app) ->
  module.app = app
  module.shutdowning = no
  module.suicide_timeout = SUICIDE_TIMEOUT
  for s in SIGNALS
    listener = SIGNAL_HANDLER_CURRYING s
    process.on s, listener
    DBG "register signal event: #{s.red}"
  return app
