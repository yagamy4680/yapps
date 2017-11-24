require! <[net mkdirp async fs path byline url through]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_findIndex} = global.get-bundled-modules!

class SocketServer
  (@name, @config, @app, @helpers, @verbose) ->
    self = @
    @uri = config.uri
    @connections = []
    server = @server = net.create-server (c) -> return self.incoming-connection c
    server.on \listen, -> DBG "#{name.cyan} (#{uri.cyan}) is listening"
    server.on \end, -> INFO "#{name.cyan} closed"
    server.on \error, (err) -> ERR err, "#{name.cyan} unexpected error"

  start: (done) ->
    {name, uri, server, verbose} = self = @
    INFO "[#{name.cyan}] #{uri.green}" if verbose
    {protocol, hostname, port, pathname} = url.parse uri
    self.protocol = protocol
    if protocol == "tcp:"
      err0 <- server.listen port, hostname
      return done "[#{name.cyan}] failed to create tcp socket server, err: #{err0}" if err0?
      INFO "[#{name.cyan}] listening #{uri.cyan}"
      return done!
    else if protocol == "unix:"
      dir = path.dirname pathname
      err0 <- mkdirp dir
      return done "[#{name.cyan}] failed to create dir #{dir}, err: #{err0}" if err0?
      INFO "[#{name.cyan}] successfully create #{dir}" if verbose
      err1, stats <- fs.stat pathname
      return done "[#{name.cyan}] #{pathname} exists but not a domain socket file" if (not err1?) and (not stats.is-socket!)
      fs.unlink-sync pathname unless err1?
      INFO "[#{name.cyan}] successfully cleanup previous domain socket" if verbose
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
    remote = "#{remote-address}:#{remote-port}"
    remote-family = "unknown" unless remote-family?
    INFO "#{name.cyan} incoming-connection: #{remote.magenta}, #{remote-family.yellow}"
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
      INFO "#{name.cyan} #{idx}(#{remote.magenta}) disconnected"
      connections.splice idx, 1 if idx?
      r.removeAllListeners \data
    c.pipe t
    return


  write-line-tokens: (tokens=[], datetime=no, delimiter='\t') ->
    xs = if datetime then ([(new Date!).toISOString!] ++ tokens) else tokens
    return @.write-line (xs.join delimiter)


  write-line: (line) ->
    {connections, verbose} = @
    INFO "line: #{line}" if verbose
    text = "#{line}\n"
    [ (c.write text) for c in connections ]


  write: (data) ->
    {connections} = @
    [ (c.write data) for c in connections ]


  to-json: ->
    {name, uri, protocol, config} = @
    {line} = config
    return {name, protocol, uri, line}


  get-connections: ->
    return @connections



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
    self.sockets = [ new SocketServer name, config, app, helpers, verbose for name, config of opts.servers ]
    self.socket-map = { [s.name, s] for s in self.sockets }
    start-server = (s, cb) -> return s.start cb
    return async.each self.sockets, start-server, done

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
    app = @
    module.manager = app.sock = new Manager opts, app, helpers


  init: (done) ->
    (err) <- module.manager.init
    WARN err, "unexpected error to initiate socket server!!" if err?
    return done!

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



