{DBG, ERR, WARN, INFO} = global.get-logger __filename
sioc = require \socket.io-client

const EVENT_READY = \ready
const EVENT_CONFIGURED = \configured
const EVENT_DATA = \data
const REQ_CONFIGURE = \configure


module.exports = exports = class WssClient
  (@server, @channel, @name=\smith, @token=null, @opts={}, @verbose=no) ->
    self = @
    ws = self.ws = sioc "#{server}/#{channel}", autoConnect: no
    ws.on \connect, -> return self.at-internal-connected!
    ws.on \disconnect, -> return self.at-internal-disconnected!
    ws.on EVENT_READY, -> return self.at-internal-ready!
    ws.on EVENT_CONFIGURED, (p) -> return self.at-internal-configured p
    ws.on EVENT_DATA, (p) -> return self.at-ws-data p


  connect: (done) -> return @.ws.connect done


  at-internal-ready: ->
    {ws, name, token, opts} = self = @
    args = [name, token, opts]
    index = new Date! - 0
    return ws.emit REQ_CONFIGURE, {index: index, args: args}


  at-internal-connected: ->
    {server, channel} = self = @
    INFO "connected to #{server} (channel: #{channel}) via websocket protocol"
    return @.at-connected @ws


  at-internal-configured: (p) ->
    {ws} = self = @
    {index, code, err} = p
    return self.at-configured ws, code, err


  at-internal-disconnected: ->
    return @.at-disconnected @ws


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


  ##
  # Subclass shall implement following methods when necessary.
  #
  at-connected: (ws) -> return
  at-disconnected: (ws) -> return
  at-configured: (ws, code, err) -> return

