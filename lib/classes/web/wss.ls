##
# WebSocket Service (helper classes)
#
# ---------------------------------------------------------------------
#
#
#
# ---------------------------------------------------------------------
# [Initialize]
# [Configure]
#
# S->C
#     `ready`     : indicate server is ready to receive packets from client.
#         payload : {}
#
# C->S
#     `configure` : request server to configure this websocket connection
#         payload :
#           - index   , the index (as integer) of the request
#           - args    , the array of arguments for configuring the behaviors of this websocket connection
#             * [0]   , the name of client, attach the this websocket connection
#             * [1]   , the service acceess token, used to authenticate when the client is not from 127.0.0.1. Could be `null`
#             * [2]   , the configurations for subclass of WsHandler to process in the function `process_configure()`
#
# S->C
#     `configured`: indicate server is configured
#         payload :
#           - index   , the index of the request paired to the response
#           - code    , the response code, `0` indicates okay.
#           - error   , the error when server configures this websocket connection, could be `null` to indicate
#                       it's okay to process the configure request.
#
#
# ---------------------------------------------------------------------
# [Request&Response], supports bi-directions: from client to server, from server to client
#
# C->S
#     `request`   : request server to perform action
#         payload :
#           - index   , the index (as integer) of the request
#           - action  , the action to be performed
#           - response, true/false to indicate the request needs response packet or not.
#           - args    , the array of arguments for performing the action at server-side
#
#     => Client's method : `submit-request`          , with arguments: (action, args, with-response, timeout=3000ms, cb=null), cb: (error, result)
#     => Handler's method: `process_request_[action]`, with arguments: (done, arg0, arg1, arg2...)
#
# S->C
#     `response`  : the response of performing the action
#         payload :
#           - index   , the index (as integer) of the request
#           - result  , the result of the action, could be `null`.
#           - error   , the error when performing the action. When `null`, it indicates successful
#                       to perform the action.
#
#
# ---------------------------------------------------------------------
# [Data], supports bi-directions: from client to server, from server to client
#
# C<->S
#     `data`   : inform peer that one data event occurs.
#         payload :
#           - index   , the index (as integer) of the data event
#           - category, the category/type of data event
#           - args    , the array of arguments, as metadata of these data items
#           - items   , the array of data items, one or more than one elements.
#
#     => Client's method : `emit-data`              , with arguments: (category, items, ...)
#     => Handler's method: `process_data_[category]`, with arguments: (items, ...)
#
#
#---
#[TODO]
# - measure the performance differences (cpu loads of both sensor-web/conscious-agent, and entire system, average in 10 minutes)
#
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{EVENT_READY, EVENT_CONFIGURED, EVENT_DATA, REQ_CONFIGURE} = require \./wss-constants
{REQUEST_CHANNEL, RESPONSE_CHANNEL, create-rr-commander} = require \./wss-helpers

const TOKEN_DEFAULT_EXPIRES = 60s

class WsHandler
  (@app, @manager, @index, @ws, @config, @ctx, @verbose) ->
    self = @
    self.name = \unknown
    self.id = ws.id
    self.ip = ws.conn.remoteAddress
    self.configured = no
    self.rrctx = null
    self.rr = null
    ws.on REQ_CONFIGURE, (p) -> return self.at-ws-configure p
    ws.on EVENT_DATA, (p) -> return self.at-ws-data p


  initiate-rr-commander: (@rrctx) ->
    {ws, manager} = self = @
    {name} = manager
    rr = self.rr = create-rr-commander name, {}, rrctx
    rr.set-outgoing-req (p) ->
      self.DEBUG "me>>peer[req]: #{JSON.stringify p}"
      return ws.emit REQUEST_CHANNEL, p
    rr.set-outgoing-rsp (p) ->
      self.DEBUG "me<<peer[rsp]: #{JSON.stringify p}"
      return ws.emit RESPONSE_CHANNEL, p
    ws.on REQUEST_CHANNEL, (p) ->
      self.DEBUG "me<<peer[req]: #{JSON.stringify p}"
      return rr.process-incoming-req p
    ws.on RESPONSE_CHANNEL, (p) ->
      self.DEBUG "me>>peer[rsp]: #{JSON.stringify p}"
      return rr.process-incoming-rsp p


  perform-req-with-rsp: (action, args=[]) ->
    {rr, verbose} = self = @
    return self.ERR "perform-req-with-rsp(): missing request-and-response commander" unless rr?
    return self.ERR "perform-req-with-rsp(): missing callback" unless args.length > 0
    done = args.pop!
    return self.ERR "perform-req-with-rsp(): last argument is not callback function" unless \function is typeof done
    if verbose
      fs = [ (JSON.stringify a) for a in args ]
      fs = fs.join ", "
      self.DEBUG "perform-req-with-rsp(): #{action}(#{fs.gray})"
    xs = [done, action, yes] ++ args
    return rr.perform-request.apply rr, xs


  perform-req-without-rsp: (action, args=[]) ->
    {rr, verbose} = self = @
    return self.ERR "perform-req-without-rsp(): missing request-and-response commander" unless rr?
    if verbose
      fs = [ (JSON.stringify a) for a in args ]
      fs = fs.join ", "
      self.DEBUG "perform-req-with-rsp(): #{action}(#{fs.gray})"
    xs = [null, action, no] ++ args
    return rr.perform-request.apply rr, xs


  get-timestamp: -> return (new Date!) - 0


  at-ws-disconnect: ->
    {ws, rr} = self = @
    self.DEBUG "at-ws-disconnect, clean up listeners"
    ws.removeAllListeners REQ_CONFIGURE
    ws.removeAllListeners EVENT_DATA
    ws.removeAllListeners REQUEST_CHANNEL if rr?
    ws.removeAllListeners RESPONSE_CHANNEL if rr?
    return


  authenticate: (name, token, done) ->
    {id, ip, manager} = self = @
    return done -10, "missing name" unless name?
    self.name = name
    self.token = token
    (err, user) <- manager.authenticate name, token, ip
    return done err[0], err[1] if err?
    {token, name} = self.user = user
    token = "null" unless token?
    self.DEBUG "accept client[#{id}]: username:#{name.cyan} token:#{token.yellow} ip:#{ip.magenta}"
    return done!

  rsp-configure-success: (index, info) ->
    {ws} = self = @
    code = 0
    payload = {index, code}
    payload['info'] = info if info?
    return ws.emit EVENT_CONFIGURED, payload

  rsp-configure-failure: (index, code, err) ->
    {ws} = self = @
    ws.emit EVENT_CONFIGURED, {index, code, err}
    f = -> ws.disconnect!
    return setTimeout f, 1000ms

  at-ws-configure: (p) ->
    {verbose, ws} = self = @
    {index, args} = p
    [name, token, opts] = args
    self.DEBUG "at-ws-configure(): name:#{name} token:#{token} opts=>#{JSON.stringify opts}"
    index = -1 unless index?
    (code, message) <- self.authenticate name, token
    return self.rsp-configure-failure index, code, message if code?
    (err, rrctx, info) <- self.process_configure opts
    return self.rsp-configure-failure index, -2, err if err?
    self.configured = yes
    self.initiate-rr-commander rrctx if rrctx?
    self.INFO "at-ws-configure(): success with info => #{JSON.stringify info}" if info?
    return self.rsp-configure-success index, info


  at-ws-data: (p) ->
    {verbose, ws} = self = @
    {index, category, items, args} = p
    return self.DEBUG "missing `index` in data event" unless index?
    return self.DEBUG "missing `category` in data event" unless category?
    return self.DEBUG "missing `items` in data event" unless items?
    name = "process_data_#{category}"
    self.DEBUG "data[#{category}]: #{JSON.stringify items} (#{JSON.stringify args})" if verbose
    args = [] unless args?
    args = [args] unless Array.isArray args
    items = [items] unless Array.isArray items
    args = [items] ++ args
    f = self[name]
    return self.DEBUG "missing handler function #{name} in subclass" unless f?
    return f.apply self, args


  emit-data: (category, items) ->
    self = @
    args = Array.from arguments
    args.shift!
    args.shift!
    self.ws.emit EVENT_DATA, do
      index: self.get-timestamp!
      category: category
      items: (if Array.isArray items then items else [items])
      args: args

  LOG: (logger, args) ->
    {verbose, name, index, ip, manager} = self = @
    a0 = args[0]
    a1 = args[1]
    message = if \object is typeof a0 then a1 else a0
    message = "#{manager.name.green}: [#{index.gray}/#{name.green}/#{ip.magenta}] #{message}"
    xs = if \object is typeof a0 then [a0, message] else [message]
    return logger.apply null, xs

  ERR: -> return @.LOG ERR, (Array.from arguments)
  INFO: -> return @.LOG INFO, (Array.from arguments)
  DEBUG: -> return @.LOG (if @verbose then INFO else DBG), (Array.from arguments)


  # Subclass shall implement following methods for different
  # purposes..
  #
  ## Process the configure-request from client, with
  ## the given options.
  ##
  ## The given callback function has 2 parameters: err, rrctx.
  ## `err` indicates successful or failed to process configurations
  ## `rrctx` is optional, as context object of request-and-response commander.
  ##
  process_configure: (opts, done) -> return done!

  ## Process the emit data from client.
  ##
  # process_data_[category1]: (items, ...) -> return
  # process_data_[category2]: (items, ...) -> return
  # process_data_[category3]: (items, ...) -> return




class WsManager
  (@wss, @app, @name, @opts, @handler-clazz, @ctx) ->
    self = @
    self.handlers = {}
    self.verbose = opts.verbose
    self.verbose = no unless self.verbose?
    self.index = 0


  init: (done) ->
    {app, name} = self = @
    {web} = app
    return done new Error "WSS depends on plugin #{'web'.yellow} but missing" unless web?
    web.useWs name, (ws) -> return self.add ws
    return done!


  force-disconnect-with-err: (ws, handler, err, message) ->
    ws.removeAllListeners \disconnect
    ws.disconnect!
    handler.at-ws-disconnect! if handler?
    ERR err, message


  add: (ws) ->
    {handlers, app, name, opts, handler-clazz, ctx, verbose} = self = @
    index = self.index = self.index + 1
    index = index.to-string!
    id = ws.id
    handler-config = opts.handler
    handler-config = {} unless handler-config?
    handler = handlers[id]
    return self.force-disconnect-with-err ws, null, "#{name.green}: duplicate identity to add: #{id}" if handler?
    handler = handlers[id] = new handler-clazz app, self, index, ws, handler-config, ctx, verbose
    ws.on \disconnect, -> return self.at-ws-disconnect id, ws, handler
    ws.emit EVENT_READY, {}
    return INFO "#{name.green}: add #{index.gray}/#{id.gray} from #{ws.conn.remoteAddress.magenta}" if verbose


  remove: (id) ->
    {handlers, name, index, verbose} = self = @
    index = index.to-string!
    return WARN "#{name.green}: missing identity to remove: #{id}" unless handlers[id]?
    {ws} = handler = handlers[id]
    delete handlers[id]
    return INFO "#{name.green}: remove #{index.gray}/#{id.gray} from #{ws.conn.remoteAddress.magenta}" if verbose


  at-ws-disconnect: (id, ws, handler) ->
    {name, verbose} = self = @
    INFO "#{name.green}: disconnect for #{id.gray} from #{ws.conn.remoteAddress.magenta}" if verbose
    ws.removeAllListeners \disconnect
    try
      handler.at-ws-disconnect!
    catch error
      ERR error, "#{name.green}[#{id}]: unexpected error when disconnect => #{error}"
    return self.remove id


  authenticate: (username, token, ip, done) ->
    return @wss.authenticate @, username, token, ip, done



class Authenticator
  (@dummy) ->
    return

  authenticate: (manager, username, token, ip, done) ->
    name = username
    user = {name, token, ip}
    return done [-11, "missing token from client #{ip}"] unless token?
    return done null, user



class DefaultAuthenticator extends Authenticator
  (@dummy) ->
    super ...
    @token = \ABCD

  authenticate: (manager, username, token, ip, done) ->
    self = @
    name = username
    user = {name, token, ip}
    return done null, user if ip is \127.0.0.1
    (err) <- super manager, username, token, ip
    return done err if err?
    return done [-12, "no valid token at server"] unless self.token?
    return done [-13, "invalid token"] unless token is self.token
    return done null, user



class Wss
  (@opts) ->
    self = @
    self.service-name = \wss
    self.managers = {}
    self.authenticator = new DefaultAuthenticator {}

  authenticate: (manager, username, token, ip, done) ->
    return @authenticator.authenticate manager, username, token, ip, done

  create-manager: (app, name, opts, handler-clazz, ctx={}) ->
    {managers, service-name} = self = @
    return new WsManager self, app, name, opts, handler-clazz, ctx unless managers[name]?
    ERR "#{service-name}: the websocket channel #{name} is already created!!"
    return null


module.wss = new Wss {}


module.exports = exports =
  create-instance: (app, name, opts, handler-clazz, ctx={}) ->
    return module.wss.create-manager app, name, opts, handler-clazz, ctx

  generate-service-token: (expire=null, token=null) ->
    return module.wss.generate-service-token expire, token

  set-authenticator: (a) ->
    return module.wss.authenticator = a

  HandlerClazz: WsHandler

  Authenticator: Authenticator

