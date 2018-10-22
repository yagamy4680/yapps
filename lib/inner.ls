require! <[path colors]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename

ERR_EXIT = (err, message) ->
  ERR err, message
  return process.exit 1


FIND_NAME_BY_INDEX_JS = ->
  return null unless global.yap-context?
  index-js-filepath = global.yap-context['__filename']
  return null unless index-js-filepath?
  tokens = index-js-filepath.split path.sep
  name = tokens[tokens.length - 2]
  DBG "detect application-name #{name.yellow} (from the path of index.js => #{index-js-filepath.cyan})"
  return name


FIND_NAME = (app-ls-filepath) ->
  name = FIND_NAME_BY_INDEX_JS!
  return name if name?
  tokens = app-ls-filepath.split path.sep
  name = tokens[tokens.length - 2]
  DBG "detect application-name #{name.yellow} (from the path of app.ls => #{app-ls-filepath.cyan})"
  return name


CREATE_APPLICATION = (type, opts, argv) ->
  {name, HELPERS} = module
  CLAZZ = if \base is type then require \./classes/BaseApp else require \./classes/WebApp
  return ERR_EXIT "the class[#{type}] of application is empty-ized" unless CLAZZ?
  try
    DBG "create #{type} with options: #{(JSON.stringify opts).green}"
    DBG "create #{type} with arguments: #{(JSON.stringify argv).green}"
    return new CLAZZ name, opts, HELPERS, argv
  catch error
    return ERR_EXIT error, "failed to create application #{type.yellow}"


module.exports = exports =

  init: (app-ls-filepath) ->
    async-executer = require \./helpers/async-executer
    deploy-config  = require \./helpers/deploy-config
    resource       = require \./helpers/resource
    system-uptime  = require \./helpers/system-uptime
    timer          = require \./helpers/timer
    signal         = require \./helpers/signal
    yapps_utils    = require \./helpers/utils
    module.HELPERS = {async-executer, deploy-config, resource, system-uptime, timer, signal}
    module.name    = name = FIND_NAME app-ls-filepath
    INFO "application name: #{name.yellow}"
    global.add-bundled-module {yapps_utils}

  create-app: (argv, type, opts) ->
    {signal} = module.HELPERS
    app_type = \base
    app_opts = {}
    if type?
      if \string is typeof type
        app_type = type
        app_opts = opts
      else if \object is typeof type
        app_opts = type
    return signal CREATE_APPLICATION app_type, app_opts, argv
