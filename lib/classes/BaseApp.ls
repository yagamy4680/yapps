require! <[fs path colors mkdirp yap-require-hook]>
require! <[async eventemitter2 handlebars]>
global.add-bundled-module {async, eventemitter2, handlebars}

{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_merge, semver, yapps_utils} = get-bundled-modules!
{SocketServer, CommandSocketConnection} = yapps_utils.classes
{PRINT_PRETTY_JSON} = yapps_utils.debug

const DEFAULT_PROCESS_RUNTIME_FILEPATH = "/tmp/yapps"


ERR_EXIT = (err, message, code=2) ->
  ERR err, message
  return process.exit code


PARSE_CMD_CONFIG_VALUE = (s, type) ->
  [prop, value] = s.split "="
  return {prop, value} unless type is \object
  return {prop, value} unless prop[0] is \^
  [prop, value] = (s.substring 1).split ":"
  value = if semver.satisfies process.version, '>=5.0' then (Buffer.from value, \base64) else (Buffer value, \base64)
  value = value.to-string \ascii
  return {prop, value}

#
# Apply command-line settings on the global configuration.
#
# E.g. "-i influxdb.server.port=13" will be applied to set
#      global.config["influxdb"]["server"]["port"] = 13
#
APPLY_CMD_CONFIG = (settings, type) ->
  if !settings then return
  settings = if settings instanceof Array then settings else [settings]
  for s in settings
    {prop, value} = PARSE_CMD_CONFIG_VALUE s, type
    INFO "applying #{prop} = #{value}"
    if '"' == value.charAt(0) and '"' == value.charAt(value.length - 1)
      value = value.substr 1, value.length - 2
    else
      if "'" == value.charAt(0) and "'" == value.charAt(value.length - 1) then value = value.substr 1, value.length - 2
    names = prop.split "."
    lastName = names.pop!
    {config} = global
    for n in names
      config = config[n]
    switch type
      | "object"    => config[lastName] = JSON.parse value
      | "string"    => config[lastName] = value
      | "integer"   => config[lastName] = parseInt value
      | "boolean"   => config[lastName] = "true" == value.toLowerCase!
      | "str_array" => config[lastName] = value.split ','
      | otherwise   => config[lastName] = value
    xs = config[lastName]
    text = "#{xs}"
    text = JSON.stringify xs if \object is typeof xs
    INFO "applied #{prop} = #{xs}"


LOAD_CONFIG = (name, argv, helpers, ctx) ->
  {resource, deploy-config} = helpers

  # Load configuration from $WORK_DIR/config/xxx.json, or .ls
  #
  {json, text, source} = resource.loadConfig argv.c
  return ERR_EXIT "failed to load #{argv.c}", null, 1 unless json?
  global.config = json
  APPLY_CMD_CONFIG argv.o, "object"
  APPLY_CMD_CONFIG argv.s, "string"
  APPLY_CMD_CONFIG argv.i, "integer"
  APPLY_CMD_CONFIG argv.b, "boolean"
  APPLY_CMD_CONFIG argv.a, "str_array"
  {config} = global

  sockpath = argv.u
  sockpath = "#{DEFAULT_PROCESS_RUNTIME_FILEPATH}/#{name}.sock" unless sockpath?
  uri = "unix://#{sockpath}"
  line = yes
  ctrl = {uri, line}
  config[\sock] = servers: {ctrl} unless config[\sock]?
  config[\sock][\servers][\ctrl] = ctrl unless config[\sock][\servers][\ctrl]?

  pidfile = argv.p
  pidfile = "#{DEFAULT_PROCESS_RUNTIME_FILEPATH}/#{name}.pid" unless pidfile?
  ppidfile = "#{pidfile}.ppid"
  config[\yapps] = process: {pidfile, ppidfile}

  return config if argv.d
  return config unless deploy-config?

  # When the mode is not deployment mode, the `config` shall be merged
  # by using itself context and APP_NAME / APP_DIR / WORK_DIR.
  #
  # The deployment environment is also decided by the environment variable: BOARD_PROFILE_ENV and YAPPS_ENV
  #
  {BOARD_PROFILE_ENV, YAPPS_ENV} = process.env
  deploy-environment = \development
  deploy-environment = YAPPS_ENV if YAPPS_ENV? and YAPPS_ENV in <[production testing development]>
  deploy-environment = BOARD_PROFILE_ENV if BOARD_PROFILE_ENV? and BOARD_PROFILE_ENV in <[production testing development]>
  colors.enabled = yes if deploy-environment is \development
  text = JSON.stringify config, null, '  '
  {error, output} = deploy-config deploy-environment, config, text, ctx
  return output unless error?
  return ERR_EXIT error, "failed to generate config with deployment option", 1


PLUGIN_INIT_CURRYING = (context, plugin, done) -->
  {instance} = plugin
  try
    return instance.init.apply context, [done]
  catch error
    return done error


PLUGIN_FINI_CURRYING = (context, plugin, done) -->
  {name, instance} = plugin
  prefix = "plugin[#{name.yellow}]"
  if instance.fini?
    try
      INFO "#{prefix}.fini() ..."
      return instance.fini.apply context, [done]
    catch error
      WARN error, "#{prefix}.fini with unexpected error"
      return done!
  else
    INFO "#{prefix}.fini() ... IGNORED."
    return done!


DATA_EMITTER_CURRYING = (app, plugin-name, resource-name, channel-name, context, data) -->
  # DBG "#{plugin-name}::#{resource-name}::#{channel-name} => #{data.length} bytes"
  evts = [plugin-name, resource-name, channel-name, \data]
  src = plugin-name: plugin-name, resource-name: resource-name, channel-name: channel-name
  app.emit evts, data, src, context
  return data


LINE_EMITTER_CURRYING = (app, plugin-name, resource-name, channel-name, context, line) -->
  # DBG "#{plugin-name}::#{resource-name}::#{channel-name} => #{line}"
  evts = [plugin-name, resource-name, channel-name, \line]
  line = "#{line}"
  line = line.substring 0, line.length - 1 if line.ends-with '\n'
  line = line.substring 0, line.length - 1 if line.ends-with '\r'
  src = plugin-name: plugin-name, resource-name: resource-name, channel-name: channel-name
  app.emit evts, line, src, context
  return line


HOOK = (err) ->
  {yap-baseapp-start-hook} = global
  yap-baseapp-start-hook err if yap-baseapp-start-hook?
  return err


LOAD_MODULE = (fullpath, done) ->
  try
    m = require fullpath
    DBG "load #{fullpath} successfully"
    return done null, m
  catch error
    ERR error, "load #{fullpath} but failed."
    return done error


class AppContext
  (@app, @opts, helpers) ->
    @system-uptime = new helpers.system-uptime {}
    @server = new eventemitter2.EventEmitter2 do
      wildcard: yes
      delimiter: \::
      newListener: no
      maxListeners: 20
    return

  init: (done) ->
    {system-uptime} = self = @
    return system-uptime.init done

  on: -> return @server.on.apply @server, arguments
  emit: -> return @server.emit.apply @server, arguments
  add-listener: -> return @server.add-listener.apply @server, arguments
  remove-listener: -> return @server.remove-listener.apply @server, arguments
  restart: (evt) -> return @app.restart evt


class AppCommandSock extends CommandSocketConnection
  (@server, @name, @c) ->
    super ...
    @app = server.parent

  process_restart: ->
    {prefix, app} = self = @
    INFO "#{prefix}: receive restart command!!"
    return WARN "already shutdowning ..." if app.shutdowning
    return app.restart \CTRL_RESTART

  process_shutdown: ->
    {prefix, app} = self = @
    INFO "#{prefix}: receive shutdown command!!"
    return WARN "already shutdowning ..." if app.shutdowning
    (err) <- app.shutdown \CTRL_SHUTDOWN
    return process.exit 0

  process_logger: (cmd, ...args) ->
    {c} = self = @
    {LOG} = global
    if cmd is \list
      names = LOG.get-logger-names!
      c.write JSON.stringify names
      c.end!
    else if cmd is \set-verbose
      [value, name] = args
      v = no
      v = yes unless value? and value is \true
      return LOG.set-logger-verbose name, value

  fallback: (cmd, args) ->
    return @.process_plugin_ctrl args if cmd in <[plugin service]>
    return WARN "unknown command to process: #{cmd.yellow} => #{JSON.stringify args}"

  process_plugin_ctrl: (args) ->
    return WARN "less than 2 arguments for service/plugin control command" unless args.length >= 2
    name = args.shift!
    return @app.process-plugin-ctrl-command name, args

  # process_xxx
  #
  # [TODO] more unixsock control commands for yapps.
  #
  # 1. Better memory analysis.
  #    https://github.com/blueconic/node-oom-heapdump
  #    Create a V8 heap snapshot right before an "Out of Memory" error occurs, or create a heap snapshot or CPU profile on request.
  #
  #     https://tech.residebrokerage.com/debugging-node-js-memory-problems-d450787d9253
  #     https://marmelab.com/blog/2018/04/03/how-to-track-and-fix-memory-leak-with-nodejs.html
  #     https://www.valentinog.com/blog/memory-usage-node-js/
  #
  #     https://www.npmjs.com/package/memwatch-next
  #
  # 2. Run a given code with vm2/sandbox, to quickly find variable value when nodejs is still running
  #
  #



class BaseApp
  (@name, @opts, @helpers, @argv) ->
    @context = new AppContext @, opts, helpers
    @plugins = []
    @plugin_map = {}
    @plugin_instances = []
    @.add-plugin require './sock'
    @shutdowning = no

  load-configs: (done) ->
    {name, helpers, argv} = self = @
    {resource} = helpers
    DUMPING = process.env.YAPPS_DUMP_LOADED_CONFIG is \true
    APP_NAME = app-name = name
    APP_DIR = resource.getAppDir!
    WORK_DIR = resource.getWorkDir!
    try
      @configs = configs = LOAD_CONFIG name, argv, helpers, {APP_NAME, APP_DIR, WORK_DIR}
      @ctrl-opts = configs[\sock][\servers][\ctrl]
      delete configs[\sock][\servers][\ctrl]
      @package-json = package-json = require "#{APP_DIR}/package.json"
      PRINT_PRETTY_JSON "app-configs", configs if DUMPING
      PRINT_PRETTY_JSON "app-package-json", package-json if DUMPING
      return done!
    catch error
      return done error

  init-control-sock: (done) ->
    ctrl = @ctrl = new SocketServer @, \ctrl, no, AppCommandSock, @ctrl-opts
    return @ctrl.start done

  init-process-files: (done) ->
    {pidfile, ppidfile} = @configs.yapps.process
    dir = path.dirname pidfile
    (dir-err) <- mkdirp dir
    return done dir-err if dir-err?
    text = "#{process.pid}"
    INFO "writing #{pidfile.cyan} with #{text.green}"
    (pid-err) <- fs.writeFile pidfile, text
    return done pid-err if pid-err?
    text = "#{process.ppid}"
    INFO "writing #{ppidfile.cyan} with #{text.green}"
    (ppid-err) <- fs.writeFile ppidfile, text
    return done ppid-err if ppid-err?
    return done!

  find-extra-plugins: (done) ->
    self = @
    {YAPPS_EXTRA_PLUGINS} = process.env
    return done! unless YAPPS_EXTRA_PLUGINS?
    return done! if YAPPS_EXTRA_PLUGINS is ""
    tokens = YAPPS_EXTRA_PLUGINS.split ':'
    tokens = [ t for t in tokens when t? and t isnt "" ]
    f = (p, cb) ->
      (err, plugin) <- LOAD_MODULE p
      return cb err if err?
      self.add-plugin plugin
      return cb!
    return async.eachSeries tokens, f, done

  attach-plugins: (done) ->
    {context, name, plugin_instances, plugins, plugin_map, configs, helpers} = self = @
    app-name = name
    app-package-json = @package-json
    app-ctrl-sock = @ctrl-opts.uri
    default-settings = {app-name, app-package-json, app-ctrl-sock}

    for p in plugin_instances
      {basename} = yap-require-hook.get-name p
      p-name = basename
      px = instance: p, name: p-name
      plugins.push px
      plugin_map[p-name] = px

      app-plugin-emitter =
        app: context
        name: p-name
        emit: ->
          {name, app} = @
          evts = [name] ++ arguments[0]
          args = Array.prototype.slice.call arguments, 1
          args = [evts] ++ args
          return app.emit.apply app, args
      try
        f = app-plugin-emitter.emit.bind app-plugin-emitter
        l = LINE_EMITTER_CURRYING self, p-name
        d = DATA_EMITTER_CURRYING self, p-name
        h = line-emitter-currying: l, data-emitter-currying: d, plugin-emitter: f
        h = lodash_merge {}, h, helpers
        c = lodash_merge {}, default-settings, configs[p-name] if configs[p-name]?
        DBG "attach plugin #{p-name.cyan} with options: #{(JSON.stringify c).green}"
        # Initialize each plugin with given options
        p.attach.apply context, [c, h]
      catch error
        return ERR_EXIT error, "failed to attach plugin #{p-name.cyan}"
    return done!

  process-plugin-ctrl-command: (name, args) ->
    {context, plugin_map} = self = @
    p = plugin_map[name]
    return WARN "no such service/plugin to process ctrl command: #{name.red}" unless p?
    {ctrl} = p.instance
    return WARN "the service/plugin #{name.red} does not support control command" unless ctrl? and \function is typeof ctrl
    return ctrl.apply context, args

  init-plugins: (done) ->
    {context, plugins, name} = @
    callbackable = done? and \function is typeof done
    (c-init-err) <- context.init
    return unless callbackable
    return ERR_EXIT c-init-err, "failed to init context" if c-init-err?
    tasks = [ (PLUGIN_INIT_CURRYING context, p) for p in plugins ]
    (p-init-err) <- async.series tasks
    return unless callbackable
    return ERR_EXIT p-init-err, "failed to init all plugins" if p-init-err?
    INFO "#{name.yellow} initialized."
    return done!

  init: (done) ->
    self = @
    (ce) <- self.load-configs
    return done HOOK ce if ce?
    (pfe) <- self.init-process-files
    return done HOOK pfe if pfe?
    (fe) <- self.find-extra-plugins
    return done HOOK fe if fe?
    (ae) <- self.attach-plugins
    return done HOOK ae if ae?
    (ie) <- self.init-plugins
    return done HOOK ie if ie?
    (ue) <- self.init-control-sock
    return done HOOK ue if ue?
    return done HOOK null

  get: (name) -> return @context[name]

  on: -> return @context.on.apply @context, arguments

  emit: -> return @context.emit.apply @context, arguments

  add-plugin: (p) -> return @plugin_instances.push p

  shutdown: (evt, done) ->
    {context, plugins, name, ctrl, shutdowning} = @
    return done "already shutdowning..." if shutdowning
    shutdowning = yes
    INFO "#{name.yellow} starts finalization with signal #{evt.red} ..."
    f = (cb) -> return ctrl.stop cb
    xs = [ p for p in plugins ]
    xs.reverse!
    tasks = [ (PLUGIN_FINI_CURRYING context, p) for p in xs ]
    tasks.unshift f
    (err) <- async.series tasks
    WARN err, "failed to finalized all plugins" if err?
    INFO "#{name.yellow} finalized."
    return done err

  restart: (evt) ->
    self = @
    (err) <- self.shutdown evt
    ERR err, "peaceful restart for signal #{evt.red} event but known error" if err?
    return process.exit 96  # refer to definitions in `signal.ls`



module.exports = exports = BaseApp
