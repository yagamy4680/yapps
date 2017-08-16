##
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
#           - action  , the action to be performed
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
require! <[colors uid]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename

const TOKEN_DEFAULT_EXPIRES = 60s

const EVENT_READY = \ready
const EVENT_CONFIGURED = \configured
const EVENT_DATA = \data
const REQ_CONFIGURE = \configure


class WsHandler
  (@app, @manager, @index, @ws, @config, @ctx, @verbose) ->
    self = @
    self.name = \unknown
    self.id = ws.id
    self.ip = ws.conn.remoteAddress
    self.configured = no
    ws.on REQ_CONFIGURE, (p) -> return self.at-ws-configure p
    ws.on EVENT_DATA, (p) -> return self.at-ws-data p
    ws.emit EVENT_READY, {}


  get-timestamp: -> return (new Date!) - 0


  at-ws-disconnect: ->
    @.DEBUG "at-ws-disconnect"
    return


  authenticate: (name, token, done) ->
    {ip, manager} = self = @
    return done -10, "missing name" unless name?
    self.name = name
    t = manager.get-service-token!
    return done! if ip is \127.0.0.1
    return done -11, "missing token from client #{ip}" unless token?
    return done -12, "no valid token at server" unless t?
    return done -13, "invalid token" unless token is t
    self.DEBUG "accept service token #{token.yellow} for client #{ip.magenta}"
    self.token = token
    manager.clear-token!
    return done!


  rsp-configure: (index, code=0, err=null) ->
    {ws} = self = @
    return ws.emit EVENT_CONFIGURED, {index: index, code: code} if code is 0
    ws.emit EVENT_CONFIGURED, {index: index, code: code, err: err}
    f = -> ws.disconnect!
    return setTimeout f, 1000ms


  at-ws-configure: (p) ->
    {verbose, ws} = self = @
    {index, args} = p
    [name, token, opts] = args
    index = -1 unless index?
    (code, message) <- self.authenticate name, token
    return self.rsp-configure index, code, message if code?
    (err) <- self.process_configure opts
    return self.rsp-configure index, -2, err if err?
    self.configured = yes
    return self.rsp-configure index


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


  DEBUG: ->
    {verbose, name, index, ip, manager} = self = @
    LOGGER = if verbose then INFO else DBG
    args = Array.from arguments
    a0 = args[0]
    a1 = args[1]
    message = if \object is typeof a0 then a1 else a0
    message = "#{manager.name.green}: [#{index.gray}/#{name.green}/#{ip.magenta}] #{message}"
    args = if \object is typeof a0 then [a0, message] else [message]
    return LOGGER.apply null, args


  # CLIENT-MUST-IMPLEMENT!!
  #
  process_configure: (opts, done) -> return




class WsManager
  (@app, @name, @opts, @handler-clazz, @ctx) ->
    self = @
    self.handlers = {}
    self.verbose = opts.verbose
    self.verbose = no unless self.verbose?
    self.index = 0
    self.token = null
    self.token-expires = 0
    self.generate-service-token TOKEN_DEFAULT_EXPIRES
    f = -> return self.at-timeout!
    self.timer = setInterval f, 1000ms


  register: (done) ->
    {app, name} = self = @
    {web} = app
    web.useWs name, (ws) -> return self.add ws
    return done!


  add: (ws) ->
    {handlers, app, name, opts, handler-clazz, ctx, verbose} = self = @
    index = self.index = self.index + 1
    index = index.to-string!
    id = ws.id
    handler-config = opts.handler
    handler-config = {} unless handler-config?
    handler = handlers[id]
    return ERR "#{name.green}: duplicate identity to add: #{id}" if handler?
    handler = handlers[id] = new handler-clazz app, self, index, ws, handler-config, ctx, verbose
    ws.on \disconnect, -> return self.at-ws-disconnect id, ws, handler
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
    try
      handler.at-ws-disconnect!
    catch error
      ERR "#{name.green}[#{id}]: unexpected error when disconnect => #{error}"
    return self.remove id


  at-timeout: ->
    {name} = self = @
    return if self.token-expires <= 0
    self.token-expires = self.token-expires - 1
    INFO "#{name.green}: token-expires => #{self.token-expires}s"
    return unless self.token-expires <= 0
    self.clear-token!


  clear-token: ->
    {name, token} = self = @
    token = "null" unless token?
    INFO "#{name.green}: clear token #{token.yellow}"
    self.token = null
    self.token-expires = 0


  get-service-token: ->
    return @token


  generate-service-token: (expire, token=null) ->
    {name} = self = @
    self.token-expires = if expire > 0 then expire else TOKEN_DEFAULT_EXPIRES
    self.token = token
    self.token = (uid 6).to-upper-case! unless self.token?
    INFO "#{name.green}: use new token #{self.token.yellow} for #{self.token-expires}s"






module.exports = exports =
  create-instance: (app, name, opts, handler-clazz, ctx={}) ->
    return new WsManager app, name, opts, handler-clazz, ctx

  HandlerClazz: WsHandler


