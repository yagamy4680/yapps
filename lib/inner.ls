require! <[path colors]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename

ERR_EXIT = (err, message) ->
  ERR err, message
  return process.exit 1


FIND_NAME = (filename) ->
  tokens = filename.split path.sep
  return tokens[tokens.length - 2]


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

  init: (app_filename) ->
    async-executer = require \./helpers/async-executer
    deploy-config  = require \./helpers/deploy-config
    resource       = require \./helpers/resource
    system-uptime  = require \./helpers/system-uptime
    timer          = require \./helpers/timer
    signal         = require \./helpers/signal
    yapps_utils    = require \./helpers/utils
    module.HELPERS = {async-executer, deploy-config, resource, system-uptime, timer, signal}
    module.name    = name = FIND_NAME app_filename
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
