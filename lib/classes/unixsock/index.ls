require! <[net mkdirp async fs path byline]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{elem-index} = require \prelude-ls

class DomainSocket
  (@name, @full-path, @app, @helpers) ->
    self = @
    @connections = []
    server = @server = net.create-server (c) -> return self.incoming-connection c
    server.on \listen, -> DBG "#{name.cyan} (#{full-path.cyan}) is listening"
    server.on \end, -> INFO "#{name.cyan} closed"
    server.on \error, (err) -> ERR err, "#{name.cyan} unexpected error"

  start: (done) ->
    self = @
    {name, full-path, server} = self
    DBG "[#{name.cyan}] enter"
    dir = path.dirname full-path
    err0 <- mkdirp dir
    return done "[#{name.cyan}] failed to create dir #{dir}, err: #{err0}" if err0?
    DBG "[#{name.cyan}] successfully create #{dir}"
    err1, stats <- fs.stat full-path
    return done "[#{name.cyan}] #{full-path} exists but not a domain socket file" if (not err1?) and (not stats.is-socket!)
    fs.unlink-sync full-path unless err1?
    DBG "[#{name.cyan}] successfully cleanup previous domain socket" if err?
    err2 <- server.listen full-path
    return done "[#{name.cyan}] failed to create domain socket, err: #{err2}" if err2?
    INFO "listening #{full-path.cyan}"
    return done!

  incoming-connection: (c) ->
    self = @
    {name, helpers, connections} = self
    {line-emitter-currying} = helpers
    {remote-address, remote-family, remote-port} = c
    DBG "#{name.cyan} incoming-connection: #{remote-address}, #{remote-family}, #{remote-port}"
    connections.push c
    f = line-emitter-currying name, \from-peer, {}
    r = byline.create-stream c
    r.on \data, f
    c.on \end, ->
      idx = connections |> elem-index c
      connections.splice idx, 1 if idx?
      DBG "#{name.cyan} #{remote-address} disconnected"
    return

  write-line: (line) ->
    {connections} = @
    INFO "line: #{line}"
    for c in connections
      c.write "#{line}\n"


class Manager
  (@sockets, @socket-map) -> return

  send-line: (name, line) ->
    s = @socket-map[name]
    return unless s?
    return s.write-line line



module.exports = exports =

  attach: (opts, helpers) ->
    app = @
    sockets = module.sockets = [new DomainSocket name, full-path, app, helpers for name, full-path of opts.servers]
    socket-map = module.socket-map = {}
    for s in sockets
      socket-map[s.name] = s
    manager = module.manager = @unixsock = new Manager sockets, socket-map


  init: (done) ->
    app = @
    {sockets, socket-map} = module
    iterator = (s, cb) -> return s.start cb
    async.each sockets, iterator, (err) ->
      DBG err, "failed to start" if err?
      return done err


/*

unixsock:
  #
  # Output events:
  #   unixsock::<name>::frome-peer::line
  #
  configurations
  servers:
    system  : '{{UNIXSOCK_DIR}}/{{APP_NAME}}.system.sock'
    data    : '{{UNIXSOCK_DIR}}/{{APP_NAME}}.data.sock'

 */
