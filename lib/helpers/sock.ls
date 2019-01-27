require! <[net mkdirp fs path byline url]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_findIndex, lodash_merge} = global.get-bundled-modules!

const DEFAULT_CONFIGS = uri: '', line: yes
const DEFAULT_DELIMITER = '\t'


class SocketConnection
  (@server, @name, @c) ->
    self = @
    {remote-address, remote-family, remote-port} = c
    @remote-address = remote-address
    @remote = remote = if remote-address? and remote-port? then "#{remote-address}:#{remote-port}" else "localhost"
    @prefix = prefix = "sock[#{name.cyan}][#{remote.magenta}]"
    remote-family = "unknown" unless remote-family?
    DBG "#{prefix}: incoming-connection => #{remote-family.yellow}"
    c.on \end, -> return self.at-end!
    c.on \error, (err) -> return self.at-error err

  finalize: ->
    {server, prefix, c} = self = @
    DBG "#{prefix}: disconnected"
    c.removeAllListeners \error
    c.removeAllListeners \data
    c.removeAllListeners \end
    return server.remove-connection self

  at-error: (err) ->
    {prefix, remote} = self = @
    ERR err, "#{prefix}: throws error, remove it from connnection-list, err: #{err}"
    return self.finalize!

  at-end: ->
    return @.finalize!

  write: ->
    return @c.write.apply @c, arguments

  end: ->
    return @c.end.apply @c, arguments

  destroy: ->
    return @c.destroy.apply @c, arguments


class CommandSocketConnection extends SocketConnection
  (@server, @name, @c) ->
    super ...
    self = @
    self.reader = byline c
    self.reader.on \data, (line) -> return self.at-line line

  at-line: (line) ->
    return unless line?
    line = line.toString!
    xs = line.split DEFAULT_DELIMITER
    cmd = xs.shift!
    return @.at-command cmd, xs

  at-command: (cmd, args) ->
    {prefix} = self = @
    cmd.trim!
    name = "process_#{cmd}"
    func = self[name]
    return func.apply self, args if func?
    return self.fallback cmd, args

  fallback: (cmd, args) ->
    return


class SocketServer
  (@parent, @name, @verbose, @clazz=SocketConnection, opts={}) ->
    self = @
    @config = lodash_merge {}, DEFAULT_CONFIGS, opts
    {uri} = @config
    @uri = uri
    @connections = []
    @prefix = prefix = "sock[#{name.cyan}]"
    server = @server = net.create-server (c) -> return self.incoming-connection c
    server.on \listen, -> DBG "#{prefix}: (#{uri.cyan}) is listening"
    server.on \end, -> INFO "#{prefix}: closed"
    server.on \error, (err) -> ERR err, "#{prefix}: unexpected error"

  start: (done) ->
    {prefix, uri, server, verbose} = self = @
    INFO "#{prefix}: #{uri.green}" if verbose
    {protocol, hostname, port, pathname} = url.parse uri
    self.protocol = protocol
    if protocol == "tcp:"
      err0 <- server.listen port, hostname
      return done "#{prefix}: failed to create tcp socket server, err: #{err0}" if err0?
      INFO "#{prefix}: listening #{uri.cyan}"
      return done!
    else if protocol == "unix:"
      dir = path.dirname pathname
      err0 <- mkdirp dir
      return done "#{prefix}: failed to create dir #{dir}, err: #{err0}" if err0?
      INFO "#{prefix}: successfully create #{dir}" if verbose
      err1, stats <- fs.stat pathname
      return done "#{prefix}: #{pathname} exists but not a domain socket file" if (not err1?) and (not stats.is-socket!)
      fs.unlink-sync pathname unless err1?
      INFO "#{prefix}: successfully cleanup previous domain socket" if verbose
      err2 <- server.listen pathname
      return done "#{prefix}: failed to create domain socket, err: #{err2}" if err2?
      INFO "listening #{pathname.cyan}"
      return done!
    else
      return done "unsupported protocol scheme: #{protocol}"

  stop: (done) ->
    {prefix, connections, server, uri} = self = @
    for let s, i in connections
      try
        INFO "#{prefix}: closing connections[#{i}] from #{s.remote-address}"
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
    {connections, prefix} = self = @
    {remote} = s
    idx = lodash_findIndex connections, s
    DBG "#{prefix}: disconnected, and remove #{remote.magenta} from slots[#{idx}]"
    return connections.splice idx, 1 if idx?

  write-line-tokens: (tokens=[], datetime=no, delimiter=DEFAULT_DELIMITER) ->
    xs = if datetime then ([(new Date!).toISOString!] ++ tokens) else tokens
    return @.write-line (xs.join delimiter)

  write-line: (line) ->
    {connections, verbose, prefix} = @
    INFO "#{prefix} => line: #{line}" if verbose
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


module.exports = exports = {SocketServer, SocketConnection, CommandSocketConnection}