{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_merge} = global.get-bundled-modules!


# Middleware: initiate web_context variable
#
INITIATION = (req, res, next) ->
  req.web_context = {}
  res.web_context = {json_wrapped: no}
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


CUSTOM_FIELD = (json, headers, field) ->
  x = headers["x-yapps-webapi-field-#{field}"]
  return unless x?
  return delete json[field] if x is \none
  json[field] = x
  return


WRAP_JSON_RESPONSE = (func) ->
  modify-response = (json, opts) ->
    {headers} = opts
    CUSTOM_FIELD json, headers, "url"     # X-YAPPS-WEBAPI-FIELD-URL
    CUSTOM_FIELD json, headers, "error"   # X-YAPPS-WEBAPI-FIELD-ERROR
    CUSTOM_FIELD json, headers, "message" # X-YAPPS-WEBAPI-FIELD-MESSAGE
    CUSTOM_FIELD json, headers, "code"    # X-YAPPS-WEBAPI-FIELD-CODE
    return json
  return (json) ->
    {headers, query} = this.req
    params = {headers, query}
    return func modify-response json, params if arguments.length is 1
    return func json unless arguments.length is 2
    return func arguments[1], modify-response json, params if \number is typeof arguments[1]
    return func json, modify-response arguments[1], params


WEBAPI_HOOK = (req, res, next) ->
  {web_context} = res
  return next! if web_context.json_wrapped? and web_context.json_wrapped
  web_context.json_wrapped = yes
  res.json = WRAP_JSON_RESPONSE res.json.bind res
  return next!


module.exports = exports = {
  INITIATION, DETECT_CLIENT_IP, GRACEFUL_SHUTDOWN, WEBAPI_HOOK
}