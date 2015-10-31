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
  {resource, ext} = helpers
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

  return config unless handlebars?      # Don't compile handlebars template when `handlebars` is empty-ized.
  try
    text = JSON.stringify config, null, '  '
    context = APP_NAME: name, APP_DIR: resource.getAppDir!, WORK_DIR: resource.getWorkDir!
    context = ext config, context
    template = handlebars.compile text
    text = template context
    config = global.config = JSON.parse text
    dump-generated-config config, text if argv.v
    return config
  catch error
    ERR error, "failed to generate config"
    process.exit 1


HOOK = (err) ->
  {yap-baseapp-start-hook} = global
  yap-baseapp-start-hook err if yap-baseapp-start-hook?
  return err


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


line-emitter-currying = (app, plugin-name, resource-name, channel-name, context, line) -->
  # DBG "#{plugin-name}::#{resource-name}::#{channel-name} => #{line}"
  evts = [plugin-name, resource-name, channel-name, \line]
  line = "#{line}"
  line = line.substring 0, line.length - 1 if line.ends-with '\n'
  line = line.substring 0, line.length - 1 if line.ends-with '\r'
  src = plugin-name: plugin-name, resource-name: resource-name, channel-name: channel-name
  return app.emit evts, line, src, context


class BaseApp
  (@name, @opts, @helpers) ->
    @context = new AppContext opts
    @plugins = []
    @plugin_instances = []
    @helpers.ext = extendify!
    this.add-plugin require './unixsock'


  init: (done) ->
    @.init-internal (err) -> return done HOOK err


  init-internal: (done) ->
    self = @
    {context, name, opts, plugin_instances, plugins, helpers} = self
    {ext} = helpers
    config = load-config name, helpers
    if not config[\unixsock]?
      config[\unixsock] = servers: system: "/tmp/yap/#{name}.system.sock"

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
        h = line-emitter-currying: l, plugin-emitter: f
        h = ext h, helpers
        c = app-name: name
        c = ext c, config[p-name] if config[p-name]?
        DBG "load plugin #{p-name.cyan} with options: #{(JSON.stringify c).green}"
        # Initialize each plugin with given options
        p.attach.apply context, [c, h]
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
