/***
  # Output events:
  #   sock::<name>::frome-peer::line
  #
  # Available object:
  #   @sock
  #   @sock.send-line (name, line)
  #
  sock:
    servers:
      system  : 'unix://{{UNIXSOCK_DIR}}/{{APP_NAME}}.system.sock'
      data    : 'unix://{{UNIXSOCK_DIR}}/{{APP_NAME}}.data.sock'
      cmd     : 'tcp://127.0.0.1:8080'

  sock:
    servers:
      system:
        uri: 'unix://{{UNIXSOCK_DIR}}/{{APP_NAME}}.system.sock'
        line: yes

      data:
        uri: 'unix://{{UNIXSOCK_DIR}}/{{APP_NAME}}.data.sock'
        line: no

      noble:
        uri: \tcp://127.0.0.1:6011
        line: yes
 */
require! <[net mkdirp async fs path byline url through]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_findIndex, yapps_utils} = global.get-bundled-modules!
{SocketServer, SocketConnection} = yapps_utils.classes


class AppSocket extends SocketConnection
  (@server, @name, @c) ->
    super ...
    {line-emitter-currying, data-emitter-currying} = module
    l = line-emitter-currying name, \from-peer, {connection: c}
    d = data-emitter-currying name, \from-peer, {connection: c}
    write = (data) -> return @.queue d data
    end = -> return @.queue null
    t = @t = through write, end
    r = @r = byline.create-stream t
    r.on \data, l
    c.pipe t
    return

  at-error: (err) ->
    @r.removeAllListeners \data
    super ...

  at-end: ->
    @r.removeAllListeners \data
    super ...


class Manager
  (@opts, @app, @helpers) ->
    @sockets = []
    @socket-map = {}
    {verbose} = opts
    @verbose = verbose
    @verbose = no unless @verbose? and @verbose
    return

  init: (done) ->
    {opts, app, helpers, verbose} = self = @
    self.sockets = [ new SocketServer self, name, verbose, AppSocket, config for name, config of opts.servers ]
    self.socket-map = { [s.name, s] for s in self.sockets }
    start-server = (s, cb) -> return s.start cb
    return async.each self.sockets, start-server, done

  fini: (done) ->
    {sockets} = self = @
    stop-server = (s, cb) -> return s.stop cb
    return async.each sockets, stop-server, done

  send-line: (name, line) ->
    s = @socket-map[name]
    return unless s?
    return s.write-line line

  send: (name, data) ->
    s = @socket-map[name]
    return unless s?
    return s.write data

  get-connections: (name) ->
    s = @socket-map[name]
    return null unless s?
    return s.connections

  get-server: (name) ->
    return @socket-map[name]


module.exports = exports =
  attach: (opts, helpers) ->
    {line-emitter-currying, data-emitter-currying} = helpers
    app = @
    module.line-emitter-currying = line-emitter-currying
    module.data-emitter-currying = data-emitter-currying
    module.manager = app.sock = new Manager opts, app, helpers

  init: (done) ->
    (err) <- module.manager.init
    WARN err, "unexpected error to initiate socket server!!" if err?
    return done!

  fini: (done) ->
    return module.manager.fini done
