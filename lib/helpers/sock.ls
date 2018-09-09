require! <[net mkdirp fs path byline url]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_findIndex, lodash_merge} = global.get-bundled-modules!

const DEFAULT_CONFIGS = uri: '', line: yes


class SocketConnection
  (@server, @name, @c) ->
    self = @
    {remote-address, remote-family, remote-port} = c
    @remote-address = remote-address
    @remote = remote = "#{remote-address}:#{remote-port}"
    remote-family = "unknown" unless remote-family?
    INFO "#{name.cyan} incoming-connection: #{remote.magenta}, #{remote-family.yellow}"
    c.on \end, -> return self.at-end!
    c.on \error, (err) -> return self.at-error err

  at-error: (err) ->
    {server, name, remote} = self = @
    ERR err, "#{name.cyan} connections[#{remote}] throws error, remove it from connnection-list, err: #{err}"
    return server.remove-connection self

  at-end: ->
    {server} = self = @
    return server.remove-connection self

  write: ->
    return @c.write.apply @c, arguments

  end: ->
    return @c.end.apply @c, arguments

  destroy: ->
    return @c.destroy.apply @c, arguments


class SocketServer
  (@parent, @name, @verbose, @clazz=SocketConnection, opts={}) ->
    self = @
    @config = lodash_merge {}, DEFAULT_CONFIGS, opts
    {uri} = @config
    @uri = uri
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

  stop: (done) ->
    {name, connections, server, uri} = self = @
    prefix = "[#{name.cyan}]"
    for let s, i in connections
      try
        INFO "#{prefix} closing connections[#{i}] from #{s.remote-address}"
        s.destroy!
        s.end!
      catch error
        ERR error, "#{prefix}: failed to close one connection => #{s.remote-address}"
    INFO "#{prefix} stop listening #{uri.cyan}"
    server.ref!
    (err) <- server.close
    WARN err, "#{prefix}: failed to close server" if err?
    return done!

  incoming-connection: (c) ->
    {connections, clazz, name} = self = @
    s = new clazz self, name, c
    connections.push s

  remove-connection: (s) ->
    {connections, name} = self = @
    {remote} = s
    idx = lodash_findIndex connections, s
    INFO "#{name.cyan} #{idx}(#{remote.magenta}) disconnected"
    return connections.splice idx, 1 if idx?

  write-line-tokens: (tokens=[], datetime=no, delimiter='\t') ->
    xs = if datetime then ([(new Date!).toISOString!] ++ tokens) else tokens
    return @.write-line (xs.join delimiter)

  write-line: (line) ->
    {connections, verbose} = @
    INFO "line: #{line}" if verbose
    text = "#{line}\n"
    [ (s.write text) for s in connections ]

  write: (data) ->
    {connections} = @
    [ (s.write data) for s in connections ]

  to-json: ->
    {name, uri, protocol, config} = @
    {line} = config
    return {name, protocol, uri, line}

  get-connections: ->
    return @connections


module.exports = exports = {SocketServer, SocketConnection}