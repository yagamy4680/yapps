require! <[path colors]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename

helpers =
  util: require \./util
  resource: require \./resource
  timer: require \./timer
  async-executer: require \./async-executer


find-app-name = (filename) ->
  tokens = filename.split path.sep
  return tokens[tokens.length - 2]


create-application = (type, opts) ->
  {app-name} = module
  {util} = helpers
  app-class = if \base == type then require \./classes/BaseApp else require \./classes/WebApp
  if not app-class?
    ERR "the app-class [#{type}] is empty-ized"
    return process.exit 1
  else
    try
      DBG "create #{type} with options: #{(JSON.stringify opts).green}"
      return new app-class app-name, opts, helpers
    catch error
      ERR error, "failed to create application #{type.yellow}"
      return process.exit 1



module.exports = exports =
  init: (app-filename) ->
    module.app-name = find-app-name app-filename
    INFO "app-name: #{module.app-name.yellow}"

  create-app: (type, opts) ->
    app_type = \base
    app_opts = {}
    if type?
      if \string == typeof type
        app_type = type
        app_opts = opts
      else if \object == typeof type
        app_opts = type
    return create-application app_type, app_opts

