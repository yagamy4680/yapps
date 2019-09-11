require! <[express body-parser handlebars fs http colors]>
ERROR_RESPONSES = require \./web-errors
{INITIATION, DETECT_CLIENT_IP, GRACEFUL_SHUTDOWN, WEBAPI_HOOK} = require \./web-middlewares

{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_merge, lodash_sum, yapps_utils} = global.get-bundled-modules!
global.add-bundled-module {express, body-parser, handlebars}


CORS = (req, res, next) ->
  # referer = req.get 'Referer'
  # Website you wish to allow to connect
  res.header 'Access-Control-Allow-Origin', 'http://localhost:6040'

  # Request methods you wish to allow
  res.header 'Access-Control-Allow-Methods', 'GET, POST, OPTIONS, PUT, PATCH, DELETE'

  # Request headers you wish to allow
  res.header 'Access-Control-Allow-Headers', 'X-Requested-With,content-type'

  # Set to true if you need the website to include cookies in the requests sent
  # to the API (e.g. in case you use sessions)
  res.setHeader 'Access-Control-Allow-Credentials', yes

  # Pass to next layer of middleware
  return next();


PARSE_VERSION_STRING = (v) ->
  xs = v.split '.'
  xs.push <[0 0]> if xs.length is 1
  xs.push <[0]> if xs.length is 2
  xs = [ (parse-int x) * (10 ^ ((xs.length - i - 1) * 2)) for let x, i in xs ]
  return lodash_sum xs


MORE_THAN_OR_EQUAL_TO = (v1, v2) ->
  x1 = PARSE_VERSION_STRING v1
  x2 = PARSE_VERSION_STRING v2
  return x1 >= x2


CLOSE_SOCKET_IO = (io, done) ->
  ##
  # socket.io 1.3
  #   Server.prototype.close = function() { ... }
  #   https://github.com/socketio/socket.io/blob/1.3.7/lib/index.js#L345
  #
  # socket.io 1.4
  #   Server.prototype.close = function() { ... }
  #   https://github.com/socketio/socket.io/blob/1.4.0/lib/index.js#L349
  #
  # socket.io 1.5
  #   Server.prototype.close = function() { ... }
  #   https://github.com/socketio/socket.io/blob/1.5.0/lib/index.js#L348
  #
  # socket.io 1.5.1
  #   Server.prototype.close = function() { ... }
  #   https://github.com/socketio/socket.io/blob/1.5.1/lib/index.js#L348
  #
  # socket.io 1.6
  #   Server.prototype.close = function(fn)
  #   https://github.com/socketio/socket.io/blob/1.6.0/lib/index.js#L359
  #
  # socket.io 1.7
  #   Server.prototype.close = function(fn) { ... }
  #   https://github.com/socketio/socket.io/blob/1.7.0/lib/index.js#L399
  #
  # ==> Since socket.io 1.6, the server.close() function supports a
  #     callback function.
  #
  if MORE_THAN_OR_EQUAL_TO (global.get-external-module-version \socket.io), \1.6
    INFO "shutting down Socket.IO engine with callback (version 1.6+)"
    return io.close done
  else
    INFO "shutting down Socket.IO engine without callback"
    io.close!
    return done!


composeError = (req, res, name, err=null, data=null) ->
  r = ERROR_RESPONSES[name]
  if r?
    template = handlebars.compile r.message
    {ip, originalUrl} = req
    msg = template {ip, originalUrl, err}
    result = code: r.code, error: name, url: originalUrl, message: msg
    result['data'] = data if data?
    INFO "err => #{err}"
    INFO "data => #{JSON.stringify data}"
    ERR "#{req.method} #{colors.yellow req.original-url} #{colors.red name} ==> #{(JSON.stringify result).cyan}"
    res.status r.status .json result
  else
    ERR "#{colors.yellow req.url} #{colors.green name} json = unknown error"
    res.status 500 .json error: "unknown error: #{name}"


composeData = (req, res, data, code=200) ->
  result =
    code: 0
    error: null
    message: null
    url: req.originalUrl
    data: data
  res.status code .json result


# Middleware: ensure only trusted ip to access the end-point
#
trusted_ip = (req, res, next) ->
  return composeError req, res, \untrusted_ip unless req.web_context.trusted_ip
  return next!


# Middleware: ensure only trusted ip or trusted user (via HTTP Basic Authentication) to access the end-point
#
trusted_ip_or_user = (req, res, next) ->
  # [todo] implement authentication with passport
  #
  # return module.auth req, res, next unless req.web_context.trusted_ip
  req.user = name: 'localhost'
  return next!


# To verify the incoming web-socket with `socketio-auth` (https://github.com/facundoolano/socketio-auth)
#
sio-authenticate-currying = (namespace, users, websocket, data, cb) -->
  {username, password} = data
  DBG "try to authenticate #{username} in namespace #{namespace.green}"
  return cb new Error "no such user `#{username}`" unless users[username]?
  return cb new Error "invalid secret" unless users[username] == password
  return cb null, yes


# After the web-socket is authenticated by `socketio-auth` (https://github.com/facundoolano/socketio-auth)
#
sio-post-authenticate-currying = (handler, websocket, data) -->
  websocket.user = data.username
  return handler websocket





class WebServer
  (@opts, @sys-helpers, @app) ->
    {resource, util} = @sys-helpers
    @web = null
    @routes = {}
    @api_routes = {}
    @wss = {}

    # Prepare helper middlewares and functions
    @helpers =
      composeError: composeError
      composeData: composeData
      trusted_ip: trusted_ip
      trusted_ip_or_user: trusted_ip_or_user

    # Default options
    DEFAULTS =
      port: 6010
      host: \0.0.0.0
      auth: yes
      headless: yes
      cors: no
      view_verbose: no
      api: 1
      upload_path: resource.resolveWorkPath 'work', 'web/upload'
      express_partial_response: yes
      express_method_overrid: yes
      express_multer: yes
      ws: {}

    # Replace with user's preferred options
    @_opts = lodash_merge {}, DEFAULTS, @opts

    INFO "user's configs: #{JSON.stringify opts}"
    INFO "default configs: #{JSON.stringify DEFAULTS}"
    INFO "merged configs: #{JSON.stringify @_opts}"

    # Directory for compiled assets (e.g. Livescript to Javascript)
    @_opts.js_dest_path = resource.resolveWorkPath \work, 'web/dest' unless @_opts.headless
    @.initiate-uploader @_opts.upload_path if @_opts.express_multer? and @_opts.express_multer


  use: (name, middleware) -> return @routes[name] = middleware unless @web?
  useApi: (name, middleware) -> return @api_routes[name] = middleware unless @web?
  useWs: (name, handler) -> return @wss[name] = handler unless @web?


  initiate-uploader: (upload-path) ->
    require! \multer
    return WARN "multer is empty-ized" unless multer?
    @helpers.upload = multer dest: upload-path
    @helpers.multer = multer
    return INFO "add multer helper"


  initiate-logger: ->
    {bunyan-logger} = @app
    return DBG "no bunyan logger plugin" unless bunyan-logger?
    eb = require \express-bunyan-logger
    return WARN "express-bunyan-logger is empty-ized" unless eb?
    web-middleware = eb do
      logger: bunyan-logger
      immediate: no
      levelFn: (status, err) ->
        return \debug if 200 == status
        return \debug if 201 == status
        return \debug if status >= 300 and status < 400
        return \info if status >= 400 and status < 500
        return \error if status >= 500
        return \warn
    @web.use web-middleware


  initiate-pug-engine: (pug-path) ->
    require! <[pug]>
    return WARN "pug is empty-ized" unless pug?
    return WARN "no view engine (the template directory #{pug-path.cyan} does not exist)" unless fs.existsSync pug-path
    @web.set 'views', pug-path
    @web.set 'view engine', \pug
    return INFO "set view engine: pug (#{pug-path.cyan})"


  initiate-favicon: (favicon-path) ->
    require! <[serve-favicon]>
    return WARN "serve-favicon is empty-ized" unless serve-favicon?
    return WARN "no favicon (the icon directory #{favicon-path.cyan} does not exist)" unless fs.existsSync favicon-path
    @web.use serve-favicon favicon-path
    return INFO "set favicon (#{favicon-path.cyan})"


  initiate-static: (name, dir) ->
    return WARN "no /#{name} (#{dir.cyan} does not exist)" unless fs.existsSync dir
    @web.use "/#{name}", express.static dir
    return INFO "add /#{name}"


  initiate-livescript-middleware: (dst-path, src-path) ->
    livescript-middleware = require './livescript-middleware'
    return WARN "livescript-middleware is empty-ized" unless livescript-middleware?
    return WARN "no livescript directory (#{src-path.cyan} does not exist)" unless fs.existsSync src-path
    @web.use livescript-middleware src: src-path, dest: dst-path
    @web.use "/", express.static dst-path
    return INFO "add /js (with livescript-middleware: #{src-path.cyan} -> #{dst-path.cyan})"


  initiate-view: ->
    {sys-helpers, _opts} = @
    {headless} = _opts
    return if headless? and headless
    {resource} = sys-helpers
    {js_dest_path} = _opts
    @.initiate-pug-engine resource.resolveResourcePath \assets, \views
    @.initiate-favicon resource.resolveResourcePath \assets, 'img/favicon.ico'
    @.initiate-static \img, resource.resolveResourcePath \assets, \img
    @.initiate-static \css, resource.resolveResourcePath \assets, \css
    @.initiate-livescript-middleware _opts.js_dest_path, resource.resolveResourcePath \assets, \ls
    @.initiate-static \js, resource.resolveResourcePath \assets, \js
    @.initiate-static \fonts, resource.resolveResourcePath \assets, \fonts


  initiate-method-override: ->
    require! <[method-override]>
    return WARN "method-override is empty-ized" unless method-override?
    @web.use method-override!
    return INFO "use middleware: method-override"


  initiate-plugin-views: ->
    {web, routes} = @
    pug-path = web.get 'views'
    for let name, m of routes
      web.use "/#{name}", m
      INFO "add /#{name}"
      if pug-path? and m.set?
        m.set 'views', pug-path
        m.set 'view engine', \pug


  initiate-plugin-api-endpoints: ->
    {web, api_routes, _opts} = @
    {express_partial_response, api} = _opts
    ep = null
    ep = require \express-partial-response if express_partial_response? and express_partial_response
    p = "/api/v#{api}"
    INFO "use #{p} (partial-response)" if ep?
    a = @api = new express!
    v = @api_v = new express!
    v.use ep! if ep?
    for let name, m of api_routes
      v.use "/#{name}", m
      uri = "#{p}/#{name}"
      INFO "api: add #{uri.yellow}"
    a.use "/v#{api}", v
    web.use "/api", WEBAPI_HOOK, a


  initiate-plugin-websockets: ->
    {server, _opts} = @
    {port, host, cors} = _opts
    sio = null
    sio = require \socket.io
    configs = {}
    # configs['origins'] = '*:*'
    # configs['transports'] = ['websocket', 'htmlfile', 'xhr-polling', 'jsonp-polling', 'polling']
    return WARN "socket.io is empty-ized" unless sio?
    sa = null
    sa = require \socketio-auth if _opts.auth
    WARN "socketio-auth is empty-ized" unless sa?
    INFO "_opts[ws] = #{JSON.stringify _opts}"
    INFO "configs = #{JSON.stringify configs}"
    io = @io = sio server, configs
    # Register different handler for incoming web-sockets in different
    # namespace.
    for let name, handler of @wss
      uri = "ws://#{host}:#{port}/#{name}"
      s = io.of name
      if sa? and _opts.ws? and _opts.ws.namespaces? and _opts.ws.namespaces[name]? and _opts.ws.namespaces[name].users?
        auth = sio-authenticate-currying name, _opts.ws.namespaces[name].users
        post-auth = sio-post-authenticate-currying handler
        # INFO "#{typeof auth}, #{typeof post-auth}"
        sa_opts = authenticate: auth, post-authenticate: post-auth
        sa s, sa_opts
        INFO "ws : add #{uri.yellow} (with authentication)"
      else
        s.on \connection, handler
        INFO "ws : add #{uri.yellow}"
      /*
      sa_opts =
        authenticate: (socket, data, callback) ->
          INFO "incoming a connection: #{data.username}"
          return callback null, true
      sa s, sa_opts
      INFO "ws : add #{uri.yellow} (with authentication always)"
      */


  start: (done) ->
    DBG "preparing middlewares ..."
    {resource} = @sys-helpers
    {port, host, upload_path, express_multer, express_method_overrid, view_verbose} = @_opts
    @web = web = express!
    @server = http.createServer @web
    web.set 'trust proxy', true
    # web.use CORS

    # My middlewares
    web.locals.shutting-down = no
    web.use GRACEFUL_SHUTDOWN
    web.use INITIATION
    web.use DETECT_CLIENT_IP

    web.use body-parser.json!
    web.use body-parser.urlencoded extended: true
    DBG "use middleware: body-parser"

    @.initiate-method-override! if express_method_overrid? and express_method_overrid

    if view_verbose? and view_verbose
      @.initiate-logger!
      @.initiate-view!
    else
      @.initiate-view!
      @.initiate-logger!

    @.initiate-plugin-views!
    @.initiate-plugin-api-endpoints!
    @.initiate-plugin-websockets!

    @server.on 'listening', ->
      p = "#{port}"
      INFO "listening #{host.yellow}:#{p.cyan}"
      return done!

    DBG "starting web server ..."
    @server.listen port, host


  stop-socket-io: (done) ->
    # [todo] We shall also close/destroy each socket connection managed by Socket.IO package,
    #        but now socket.io package is relatively old (1.3.7).
    #        After upgrading to Socket.IO 2.0.0 (https://socket.io/blog/socket-io-2-0-0/)
    #        with `uws`, then we can consider to implement this logic aspired by
    #        https://github.com/emostar/express-graceful-exit/blob/master/lib/graceful-exit.js#L81-L106
    #
    {io} = self = @
    return done! unless io?
    {sockets} = io.sockets
    INFO "shutting down Socket.IO engine and Http Server"
    (err) <- CLOSE_SOCKET_IO io
    return done err if err?
    # INFO "sockets? => #{sockets?}"
    # INFO "typeof sockets => #{typeof sockets}"
    # INFO "Array.isArray sockets => #{Array.isArray sockets}"
    connections = null
    if sockets? and \object is typeof sockets and not Array.isArray sockets
      INFO "socket.io 1.4+, sockets are key-value pairs"
      for name, c of sockets
        INFO "socket.io[#{name.cyan}] disconnecting ..."
        c.disconnect!
    else if sockets? and sockets.length?
      INFO "socket.io 1.0 ~ 1.3, sockets are array"
      for let c, i in sockets
        t = "#{i}"
        INFO "socket.io[#{t.cyan}] disconnecting ..."
        c.disconnect!
    else
      INFO "socket.io 0.X, using clients()"
      for let c, i in sockets.clients!
        t = "#{i}"
        INFO "socket.io[#{t.cyan}] disconnecting ..."
        c.disconnect!
    return done!


  stop: (done) ->
    {web, server, _opts} = self = @
    {host, port} = _opts
    port = "#{port}"
    if not web?
      WARN "shutting down Express engine but missing"
      return done!
    INFO "shutting down Express engine"
    web.locals.shutting-down = yes
    (io-close-err) <- self.stop-socket-io
    WARN io-close-err, "failed to shutdown Socket.IO engine" if io-close-err?
    return WARN "shutting down Http Server listening #{host.yellow}:#{port.cyan} but missing" unless server?
    INFO "shutting down Http Server listening #{host.yellow}:#{port.cyan}"
    (err) <- server.close
    WARN err, "failed to shutdown http server" if err? and err.message is not "Not running" # socketio.close() shall also close http server.
    return done!



module.exports = exports =

  attach: (opts, helpers) ->
    module.opts = opts
    module.helpers = helpers
    web = module.web = @web = new WebServer opts, helpers, @


  init: (done) ->
    {helpers} = module
    {web} = @
    {_opts} = web
    dirs = [_opts.upload_path]
    dirs.push _opts.js_dest_path unless _opts.headless
    return yapps_utils.CREATE_DIRECTORIES dirs, done


  fini: (done) ->
    return module.web.stop done

