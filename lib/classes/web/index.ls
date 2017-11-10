require! <[express fs http colors]>
error_responses = require \./web_errors
{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_merge} = global.get-bundled-modules!

global.add-bundled-module {express}

composeError = (req, res, name, err = null) ->
  require! <[handlebars]>
  if error_responses[name]?
    r = error_responses[name]
    template = handlebars.compile r.message
    context = ip: req.ip, originalUrl: req.originalUrl, err: err
    msg = template context
    result =
      code: r.code
      error: name
      url: req.originalUrl
      message: msg
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


# Middleware: detect the client's ip address is trusted or not, and save result at web_context.trusted_ip
#
detectClientIp = (req, res, next) ->
  ip = req.ip
  web_context = req.web_context
  web_context.trusted_ip = false
  web_context.trusted_ip = true if ip == "127.0.0.1"
  # web_context.trusted_ip = true if ip.startsWith "192.168."
  next!


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
    @_opts =
      port: 6010
      host: \0.0.0.0
      headless: yes
      view_verbose: no
      api: 1
      upload_path: resource.resolveWorkPath 'work', 'web/upload'
      express_partial_response: yes
      express_method_overrid: yes
      express_multer: yes
      ws: {}

    # Replace with user's preferred options
    # fields = [ k for k, v of @_opts ]
    # @_opts = util.copy-object @_opts, @opts, fields
    @_opts = lodash_merge @_opts, @opts

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


  initiate-jade-engine: (jade-path) ->
    require! <[jade]>
    return WARN "jade is empty-ized" unless jade?
    return WARN "no view engine (the template directory #{jade-path.cyan} does not exist)" unless fs.existsSync jade-path
    @web.set 'views', jade-path
    @web.set 'view engine', \jade
    return INFO "set view engine: jade (#{jade-path.cyan})"


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
    @.initiate-jade-engine resource.resolveResourcePath \assets, \views
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
    jade-path = web.get 'views'
    for let name, m of routes
      web.use "/#{name}", m
      INFO "add /#{name}"
      if jade-path?
        m.set 'views', jade-path
        m.set 'view engine', \jade


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
    web.use "/api", a


  initiate-plugin-websockets: ->
    {server, _opts} = @
    {port, host} = _opts
    sio = null
    sio = require \socket.io
    return WARN "socket.io is empty-ized" unless sio?
    sa = require \socketio-auth
    WARN "socketio-auth is empty-ized" unless sa?
    INFO "_opts[ws] = #{JSON.stringify _opts}"
    io = @io = sio server
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

    require! <[body-parser]>
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

    # My middlewares
    web.use initiation
    web.use detectClientIp

    @.initiate-plugin-views!
    @.initiate-plugin-api-endpoints!
    @.initiate-plugin-websockets!

    @server.on 'listening', ->
      p = "#{port}"
      INFO "listening #{host.yellow}:#{p.cyan}"
      return done!

    DBG "starting web server ..."
    @server.listen port, host



# Middleware: initiate web_context variable
#
initiation = (req, res, next) ->
  req.web_context = {}
  next!



module.exports = exports =

  attach: (opts, helpers) ->
    module.opts = opts
    module.helpers = helpers
    web = module.web = @web = new WebServer opts, helpers, @


  init: (done) ->
    {helpers} = module
    {web} = @
    {_opts} = web
    {util} = helpers
    dirs = [_opts.upload_path]
    dirs.push _opts.js_dest_path unless _opts.headless
    util.createDirectories dirs, (err) -> return done err

