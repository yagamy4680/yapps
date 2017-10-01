require! <[path async colors optimist extendify eventemitter2 yap-require-hook handlebars]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename

#
# Apply command-line settings on the global configuration.
#
# E.g. "-i influxdb.server.port=13" will be applied to set
#      global.config["influxdb"]["server"]["port"] = 13
#
apply-cmd-config = (settings, type) ->
  if !settings then return
  settings = if settings instanceof Array then settings else [settings]
  for s in settings
    tokens = s.split "="
    prop = tokens[0]
    value = tokens[1]
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
      | "string"    => config[lastName] = value
      | "integer"   => config[lastName] = parseInt value
      | "boolean"   => config[lastName] = "true" == value.toLowerCase!
      | "str_array" => config[lastName] = value.split ','
      | otherwise   => config[lastName] = value
    INFO "applying #{prop} = #{config[lastName]}"


dump-generated-config = (config, text) ->
  require! <[prettyjson]>
  return console.error "generated configuration: \n#{text.gray}" unless prettyjson?
  text = prettyjson.render config, do
    keysColor: \gray
    dashColor: \green
    stringColor: \yellow
    numberColor: \cyan
    defaultIndentation: 4
  xs = text.split '\n'
  console.error "generated configration:"
  for x in xs
    console.error "\t#{x}"
  console.error ""
  # return console.error "generated configuration:\n#{text}\n"


load-config = (name, helpers) ->
  {resource, ext, deploy-config} = helpers
  opt = optimist.usage 'Usage: $0'
    .alias 'c', 'config'
    .describe 'c', 'the configuration set, might be default, bbb0, ...'
    .default 'c', 'default'
    .alias 'd', 'deployment'
    .describe 'd', 'deployment mode or not'
    .default 'd', no
    .alias 'b', 'config_bool'
    .describe 'b', 'overwrite a configuration with boolean value, e.g. -b "system.influxServer.secure=false"'
    .alias 's', 'config_string'
    .describe 's', 'overwrite a configuration with boolean value, e.g. -b "system.influxServer.user=smith"'
    .alias 'i', 'config_int'
    .describe 'i', 'overwrite a configuration with int value, e.g. -b "behavior.notify.influxPeriod=smith"'
    .alias 'a', 'config_str_array'
    .describe 'a', 'overwrite a configuration with array of strings with delimiter character `COMMA`, e.g. -b "system.influxServer.clusters=aa.test.net,bb.test.net,cc.test.net"'
    .alias 'v', 'verbose'
    .describe 'v', 'verbose message output (level is changed to `debug`)'
    .default 'v', false
    .alias 'q', 'quiet'
    .describe 'q', 'disable logging outputs to local file, but still outputs to stderr'
    .default 'q', false
    .boolean <[h v]>
  argv = global.argv = opt.argv

  if argv.h
    opt.showHelp!
    process.exit 0

  # Load configuration from $WORK_DIR/config/xxx.json, or .ls
  #
  {json, text, source} = resource.loadConfig argv.config
  global.config = json
  return process.exit 1 unless json?

  apply-cmd-config argv.s, "string"
  apply-cmd-config argv.i, "integer"
  apply-cmd-config argv.b, "boolean"
  apply-cmd-config argv.a, "str_array"

  {config} = global
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
  context = APP_NAME: name, APP_DIR: resource.getAppDir!, WORK_DIR: resource.getWorkDir!
  text = JSON.stringify config, null, '  '
  {error, output} = deploy-config deploy-environment, config, text, context
  return output unless error?
  ERR error, "failed to generate config with deployment option"
  return process.exit 1



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
  (@opts) ->
    @server = new eventemitter2.EventEmitter2 do
      wildcard: yes
      delimiter: \::
      newListener: no
      maxListeners: 20
    return

  on: -> return @server.on.apply @server, arguments
  emit: -> return @server.emit.apply @server, arguments
  add-listener: -> return @server.add-listener.apply @server, arguments



data-emitter-currying = (app, plugin-name, resource-name, channel-name, context, data) -->
  # DBG "#{plugin-name}::#{resource-name}::#{channel-name} => #{data.length} bytes"
  evts = [plugin-name, resource-name, channel-name, \data]
  src = plugin-name: plugin-name, resource-name: resource-name, channel-name: channel-name
  app.emit evts, data, src, context
  return data


line-emitter-currying = (app, plugin-name, resource-name, channel-name, context, line) -->
  # DBG "#{plugin-name}::#{resource-name}::#{channel-name} => #{line}"
  evts = [plugin-name, resource-name, channel-name, \line]
  line = "#{line}"
  line = line.substring 0, line.length - 1 if line.ends-with '\n'
  line = line.substring 0, line.length - 1 if line.ends-with '\r'
  src = plugin-name: plugin-name, resource-name: resource-name, channel-name: channel-name
  app.emit evts, line, src, context
  return line


class BaseApp
  (@name, @opts, @helpers) ->
    @context = new AppContext opts
    @plugins = []
    @plugin_instances = []
    @helpers.ext = extendify!
    @.add-plugin require './sock'


  init-extra-plugins: (done) ->
    self = @
    {YAPPS_EXTRA_PLUGINS} = process.env
    return done! unless YAPPS_EXTRA_PLUGINS?
    return done! if YAPPS_EXTRA_PLUGINS is ""
    tokens = YAPPS_EXTRA_PLUGINS.split ':'
    f = (p, cb) ->
      (err, plugin) <- LOAD_MODULE p
      return cb err if err?
      self.add-plugin plugin
      return cb!
    return async.eachSeries tokens, f, done


  init: (done) ->
    self = @
    (ee) <- self.init-extra-plugins
    return done HOOK ee if ee?
    (ie) <- self.init-internal
    return done HOOK ie


  init-internal: (done) ->
    self = @
    {context, name, opts, plugin_instances, plugins, helpers} = self
    {ext} = helpers
    config = load-config name, helpers
    sys-sock = uri: "unix:///tmp/yap/#{name}.system.sock", line: yes
    config[\sock] = servers: system: sys-sock unless config[\sock]?
    config[\sock][\servers][\system] = sys-sock unless config[\sock][\servers][\system]?
    dump-generated-config config, (JSON.stringify config, null, ' ')

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
        l = line-emitter-currying self, p-name
        d = data-emitter-currying self, p-name
        h = line-emitter-currying: l, data-emitter-currying: d, plugin-emitter: f
        h = ext h, helpers
        c = app-name: name
        c = ext c, config[p-name] if config[p-name]?
        DBG "load plugin #{p-name.cyan} with options: #{(JSON.stringify c).green}"
        # Initialize each plugin with given options
        p.attach.apply context, [c, h]
      catch error
        ERR error, "failed to load plugin #{p-name.cyan}"
        process.exit 2
    return self.init-each-plugin done


  init-each-plugin: (done) ->
    {context, plugins, name} = @
    f_currying = (context, plugin, cb) -->
      try
        {instance} = plugin
        return instance.init.apply context, [cb]
      catch error
        return cb error
    tasks = [ f_currying context, p for p in plugins ]
    async.series tasks, (err) ->
      return unless done? and \function == typeof done
      if err?
        WARN err, "failed to init all plugins" if err?
        process.exit 2
      else
        INFO "#{name.yellow} initialized."
        return done!


  get: (name) -> return @context[name]

  on: -> return @context.on.apply @context, arguments

  emit: -> return @context.emit.apply @context, arguments

  add-plugin: (p) -> return @plugin_instances.push p


module.exports = exports = BaseApp
