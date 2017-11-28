{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_merge} = global.get-bundled-modules!


# Middleware: initiate web_context variable
#
INITIATION = (req, res, next) ->
  req.web_context = {}
  next!


# Middleware: detect the client's ip address is trusted or not, and save result at web_context.trusted_ip
#
DETECT_CLIENT_IP = (req, res, next) ->
  ip = req.ip
  web_context = req.web_context
  web_context.trusted_ip = false
  web_context.trusted_ip = true if ip == "127.0.0.1"
  # web_context.trusted_ip = true if ip.startsWith "192.168."
  next!


# Middleware: graceful shutdown
#
# Inspired by
#   - https://github.com/serby/express-graceful-shutdown/blob/master/index.js#L36-L40
#   - https://github.com/emostar/express-graceful-exit/blob/master/lib/graceful-exit.js#L134-L149
#
#
GRACEFUL_SHUTDOWN = (req, res, next) ->
  # The flag `shutting-down` is used to tell the middleware we create that
  # server wants to stop, so we do not allow anymore connection. This is
  # done for all new connections for us by Node, but we need to handle
  # the connections that are using the Keep-Alive header to stay on.
  #
  {locals} = req.app
  {shutting-down} = locals
  return next! unless shutting-down? and shutting-down
  INFO "close http connection immediately!!"
  res.set 'Connection', 'close'
  res.status 503 .send 'Server is in the process of restarting.'
  req.connection.setTimeout 1
  return


module.exports = exports = {INITIATION, DETECT_CLIENT_IP, GRACEFUL_SHUTDOWN}