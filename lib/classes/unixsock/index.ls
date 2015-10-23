require! <[net mkdirp async fs path byline]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename

class DomainSocket
  (@name, @full-path, @app, @helpers) ->
    self = @
    f = (c) -> return self.incoming-connection c
    @connections = []
    server = @server = net.create-server f
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
    INFO "listening #{full-path.yellow}"
    return done!

  incoming-connection: (c) ->
    self = @
    {name, helpers} = self
    {line-emitter-currying} = helpers
    {remote-address, remote-family, remote-port} = c
    DBG "#{name.cyan} incoming-connection: #{remote-address}, #{remote-family}, #{remote-port}"
    f = line-emitter-currying name, \from-peer, {}
    c.on \end, -> DBG "#{name.cyan} #{remote-address} disconnected"
    r = byline.create-stream c
    r.on \data, f
    return




module.exports = exports =

  attach: (opts, helpers) ->
    app = @
    sockets = module.sockets = [new DomainSocket name, full-path, app, helpers for name, full-path of opts.servers]

  init: (done) ->
    {sockets} = module
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
  # Accept events:
  #   unixsock::<name>::to-peer::line
  #
  servers:
    system  : '{{UNIXSOCK_DIR}}/{{APP_NAME}}.system.sock'
    data    : '{{UNIXSOCK_DIR}}/{{APP_NAME}}.data.sock'

 */
