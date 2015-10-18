require! <[path async colors optimist extendify eventemitter2 yap-require-hook]>
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


load-config = (helpers) ->
  {resource} = helpers
  opt = optimist.usage 'Usage: $0'
    .alias 'c', 'config'
    .describe 'c', 'the configuration set, might be default, bbb0, ...'
    .default 'c', 'default'
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
  config = global.config = resource.loadConfig argv.config
  return process.exit 1 unless config?

  apply-cmd-config argv.s, "string"
  apply-cmd-config argv.i, "integer"
  apply-cmd-config argv.b, "boolean"
  apply-cmd-config argv.a, "str_array"
  return config



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



class BaseApp
  (@name, @opts, @helpers) ->
    @context = new AppContext opts
    @plugins = []
    @plugin_instances = []
    @helpers.ext = extendify!

  add-plugin: (p) -> return @plugin_instances.push p

  init: (done) ->
    {context, name, opts, plugin_instances, plugins, helpers} = @
    {ext} = helpers
    config = load-config helpers
    for p in plugin_instances
      {basename} = yap-require-hook.get-name p
      p-name = basename
      px = instance: p, name: p-name
      plugins.push px
      try
        c = app-name: name
        c = ext c, config[p-name] if config[p-name]?
        c = ext c, opts-overrided if opts-overrided?
        DBG "load plugin #{p-name.cyan} with options: #{(JSON.stringify c).green}"
        # Initialize each plugin with given options
        p.attach.apply context, [c, helpers]
      catch error
        ERR error, "failed to load plugin"
        process.exit 2
    return @.init-each-plugin done


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
      return done err if err?
      INFO "#{name.yellow} initialized."
      return done!

  get: (name) -> return @context[name]

  on: -> return @context.on.apply @context, arguments

  emit: -> return @context.emit.apply @context, arguments


module.exports = exports = BaseApp