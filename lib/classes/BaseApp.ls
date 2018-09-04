require! <[fs path colors mkdirp yap-require-hook]>
require! <[async optimist eventemitter2 handlebars]>
global.add-bundled-module {async, optimist, eventemitter2, handlebars}

{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_merge, semver, yapps_utils} = get-bundled-modules!
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


LOAD_CONFIG = (name, helpers, ctx) ->
  {resource, deploy-config} = helpers
  opt = optimist.usage 'Usage: $0'
    .alias    \c, \config
    .describe \c, 'the name of deployment configuration, e.g. production, development, testing...'
    .default  \c, \default
    .alias    \p, \pidfile
    .describe \p, 'PID file'
    .default  \p, null
    .alias    \u, \unixsock
    .describe \u, ''
    .default  \u, null
    .alias    \d, \deployment
    .describe \d, 'deployment mode or not'
    .default  \d, no
    .alias    \v, \verbose
    .describe \v, 'verbose message output (level is changed to `debug`)'
    .default  \v, false
    .alias    \q, \quiet
    .describe \q, 'disable logging outputs to local file, but still outputs to stderr'
    .default  \q, false
    .alias    \b, 'config_bool'
    .describe \b, 'overwrite a configuration with boolean value, e.g. -b "system.influxServer.secure=false"'
    .alias    \s, 'config_string'
    .describe \s, 'overwrite a configuration with string value, e.g. -s "system.influxServer.user=smith"'
    .alias    \i, 'config_int'
    .describe \i, 'overwrite a configuration with int value, e.g. -i "behavior.notify.influxPeriod=3000"'
    .alias    \a, 'config_str_array'
    .describe \a, 'overwrite a configuration with array of strings with delimiter character `COMMA`, e.g. -a "system.influxServer.clusters=aa.test.net,bb.test.net,cc.test.net"'
    .alias    \o, 'config_object'
    .describe \o, 'overwrite a configuration with json object string, e.g. -o "system.influxServer.connections.ifdb999={"url":"tcp://192.168.1.110:6020","enabled":false}"'
    .boolean <[h v q]>
  argv = global.argv = opt.argv

  if argv.h
    opt.showHelp!
    process.exit 0

  # Load configuration from $WORK_DIR/config/xxx.json, or .ls
  #
  {json, text, source} = resource.loadConfig argv.config
  return ERR_EXIT "failed to load #{argv.config}", null, 1 unless json?
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
  system = {uri, line}
  config[\sock] = servers: {system} unless config[\sock]?
  config[\sock][\servers][\system] = system unless config[\sock][\servers][\system]?

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
    ## maybe to be removed
    ## -------------------------
    cb = (err) ->
      WARN err, "#{prefix}.fini with unexpected error" if err?
      return done!
    ## -------------------------
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
  (@opts, helpers) ->
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


class BaseApp
  (@name, @opts, @helpers) ->
    @context = new AppContext opts, helpers
    @plugins = []
    @plugin_instances = []
    @.add-plugin require './sock'

  load-configs: (done) ->
    {name, helpers} = self = @
    {resource} = helpers
    DUMPING = process.env.YAPPS_DUMP_LOADED_CONFIG is \true
    APP_NAME = app-name = name
    APP_DIR = resource.getAppDir!
    WORK_DIR = resource.getWorkDir!
    try
      @configs = configs = LOAD_CONFIG name, helpers, {APP_NAME, APP_DIR, WORK_DIR}
      @package-json = package-json = require "#{APP_DIR}/package.json"
      PRINT_PRETTY_JSON "app-configs", configs unless DUMPING
      PRINT_PRETTY_JSON "app-package-json", package-json unless DUMPING
      return done!
    catch error
      return done error

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
    {context, name, plugin_instances, plugins, configs, helpers} = self = @
    app-name = name
    app-package-json = @package-json
    default-settings = {app-name, app-package-json}

    for p in plugin_instances
      {basename} = yap-require-hook.get-name p
      p-name = basename
      px = instance: p, name: p-name
      plugins.push px

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
    return done HOOK ie

  get: (name) -> return @context[name]

  on: -> return @context.on.apply @context, arguments

  emit: -> return @context.emit.apply @context, arguments

  add-plugin: (p) -> return @plugin_instances.push p

  shutdown: (evt, done) ->
    {context, plugins, name} = @
    INFO "#{name.yellow} starts finalization with signal #{evt.red} ..."
    xs = [ p for p in plugins ]
    xs.reverse!
    tasks = [ (PLUGIN_FINI_CURRYING context, p) for p in xs ]
    (err) <- async.series tasks
    code = if err? then 1 else 0
    WARN err, "failed to finalized all plugins" if err?
    INFO "#{name.yellow} finalized."
    return done null, code


module.exports = exports = BaseApp
