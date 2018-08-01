{DBG, ERR, WARN, INFO} = global.get-logger __filename
{EVENT_READY, EVENT_CONFIGURED, EVENT_DATA, REQ_CONFIGURE} = require \./wss-constants
{REQUEST_CHANNEL, RESPONSE_CHANNEL, create-rr-commander} = require \./wss-helpers


module.exports = exports = class WssClient
  (@sioc, @host, @channel, @name=\smith, @token=null, @opts={}, @verbose=no, @rrctx=null, @rr-opts={}) ->
    self = @
    self.configured = no
    self.rr = null
    ws = self.ws = sioc "#{host}/#{channel}", autoConnect: yes
    ws.on \connect, -> return self.at-internal-connected!
    ws.on \disconnect, -> return self.at-internal-disconnected!
    ws.on EVENT_READY, -> return self.at-internal-ready!
    ws.on EVENT_CONFIGURED, (p) -> return self.at-internal-configured p
    ws.on EVENT_DATA, (p) -> return self.at-ws-data p
    return unless rrctx?
    self.opts.rrctx = rrctx.set-wssc self
    rr = self.rr = create-rr-commander name, rr-opts, rrctx
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


  connect: (done) -> return @ws.connect done


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


  at-internal-ready: ->
    {ws, name, token, opts} = self = @
    args = [name, token, opts]
    index = new Date! - 0
    return ws.emit REQ_CONFIGURE, {index, args}


  at-internal-connected: ->
    {host, channel} = self = @
    INFO "connected to #{host} (channel: #{channel}) via websocket protocol"
    return @.at-connected @ws


  at-internal-configured: (p) ->
    {ws} = self = @
    {index, code, err, info} = p
    self.configured = code is 0
    self.at-configured ws, code, err, info
    return ws.disconnect! unless code is 0


  at-internal-disconnected: ->
    {ws, rr} = self = @
    self.configured = no
    # self.DEBUG "at-ws-disconnect, clean up listeners"
    # ws.removeAllListeners REQ_CONFIGURE
    # ws.removeAllListeners EVENT_DATA
    # ws.removeAllListeners REQUEST_CHANNEL if rr?
    # ws.removeAllListeners RESPONSE_CHANNEL if rr?
    return self.at-disconnected ws


  at-ws-data: (p) ->
    {verbose, ws} = self = @
    {index, category, items, args} = p
    return WARN "missing `index` in data event" unless index?
    return WARN "missing `category` in data event" unless category?
    return WARN "missing `items` in data event" unless items?
    name = "process_data_#{category}"
    # INFO "data[#{category}]: #{JSON.stringify items} (#{JSON.stringify args})" if verbose
    args = [] unless args?
    args = [args] unless Array.isArray args
    items = [items] unless Array.isArray items
    args = [items] ++ args
    f = self[name]
    return WARN "missing handler function #{name} in subclass" unless f?
    return f.apply self, args


  emit-data: (category, items, args) ->
    {ws, configured} = self = @
    return unless configured
    index = new Date! - 0
    ws.emit EVENT_DATA, {index, category, items, args}


  ERR: ->
    {verbose, name, index} = self = @
    LOGGER = ERR
    args = Array.from arguments
    a0 = args[0]
    a1 = args[1]
    message = if \object is typeof a0 then a1 else a0
    message = "#{name.green}: [#{index.gray}] #{message}"
    args = if \object is typeof a0 then [a0, message] else [message]
    return LOGGER.apply null, args


  DEBUG: ->
    {verbose, name, channel} = self = @
    LOGGER = if verbose then INFO else DBG
    args = Array.from arguments
    a0 = args[0]
    a1 = args[1]
    message = if \object is typeof a0 then a1 else a0
    message = "#{name.green}: [#{channel.gray}] #{message}"
    args = if \object is typeof a0 then [a0, message] else [message]
    return LOGGER.apply null, args


  ##
  # Subclass shall implement following methods when necessary.
  #
  at-connected: (ws) -> return
  at-disconnected: (ws) -> return
  at-configured: (ws, code, err) -> return

