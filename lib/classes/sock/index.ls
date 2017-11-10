require! <[net mkdirp async fs path byline url through]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_findIndex} = global.get-bundled-modules!

class SocketServer
  (@name, @config, @app, @helpers) ->
    self = @
    @uri = config.uri
    @connections = []
    server = @server = net.create-server (c) -> return self.incoming-connection c
    server.on \listen, -> DBG "#{name.cyan} (#{uri.cyan}) is listening"
    server.on \end, -> INFO "#{name.cyan} closed"
    server.on \error, (err) -> ERR err, "#{name.cyan} unexpected error"

  start: (done) ->
    self = @
    {name, uri, server} = self
    DBG "[#{name.cyan}] #{uri.green}"
    {protocol, hostname, port, pathname} = url.parse uri
    if protocol == "tcp:"
      err0 <- server.listen port, hostname
      return done "[#{name.cyan}] failed to create tcp socket server, err: #{err0}" if err0?
      INFO "[#{name.cyan}] listening #{uri.cyan}"
      return done!
    else if protocol == "unix:"
      dir = path.dirname pathname
      err0 <- mkdirp dir
      return done "[#{name.cyan}] failed to create dir #{dir}, err: #{err0}" if err0?
      DBG "[#{name.cyan}] successfully create #{dir}"
      err1, stats <- fs.stat pathname
      return done "[#{name.cyan}] #{pathname} exists but not a domain socket file" if (not err1?) and (not stats.is-socket!)
      fs.unlink-sync pathname unless err1?
      DBG "[#{name.cyan}] successfully cleanup previous domain socket" if err?
      err2 <- server.listen pathname
      return done "[#{name.cyan}] failed to create domain socket, err: #{err2}" if err2?
      INFO "listening #{pathname.cyan}"
      return done!
    else
      return done "unsupported protocol scheme: #{protocol}"


  incoming-connection: (c) ->
    self = @
    {name, helpers, connections, app} = self
    {line-emitter-currying, data-emitter-currying} = helpers
    {remote-address, remote-family, remote-port} = c
    INFO "#{name.cyan} incoming-connection: #{remote-address}, #{remote-family}, #{remote-port}"
    connections.push c

    l = line-emitter-currying name, \from-peer, {connection: c}
    d = data-emitter-currying name, \from-peer, {connection: c}

    write = (data) -> return @.queue d data
    end = -> return @.queue null

    t = through write, end
    r = byline.create-stream t
    r.on \data, l
    c.on \error, (err) ->
      idx = lodash_findIndex connections, c
      ERR err, "#{name.cyan} connections[#{idx}[ throws error, remove it from connnection-list, err: #{err}"
      connections.splice idx, 1 if idx?
      r.removeAllListeners \data
    c.on \end, ->
      idx = lodash_findIndex connections, c
      INFO "#{name.cyan} #{idx}(#{remote-address}) disconnected"
      connections.splice idx, 1 if idx?
      r.removeAllListeners \data
    c.pipe t
    return


  write-line: (line) ->
    {connections} = @
    DBG "line: #{line}"
    for c in connections
      c.write "#{line}\n"


  write: (data) ->
    {connections} = @
    for c in connections
      c.write data



class Manager
  (@sockets, @socket-map) -> return

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


module.exports = exports =

  attach: (opts, helpers) ->
    app = @
    sockets = module.sockets = [new SocketServer name, config, app, helpers for name, config of opts.servers]
    socket-map = module.socket-map = {}
    for s in sockets
      socket-map[s.name] = s
    manager = module.manager = @sock = new Manager sockets, socket-map


  init: (done) ->
    app = @
    {sockets, socket-map} = module
    iterator = (s, cb) -> return s.start cb
    async.each sockets, iterator, (err) ->
      DBG err, "failed to start" if err?
      return done err


/*
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



