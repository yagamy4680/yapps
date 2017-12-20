require! <[path colors]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename

async-executer= require \./helpers/async-executer
deploy-config = require \./helpers/deploy-config
resource      = require \./helpers/resource
system-uptime = require \./helpers/system-uptime
timer         = require \./helpers/timer
#util          = require \./helpers/utils
#HELPERS       = {async-executer, deploy-config, resource, system-uptime, timer, util}
HELPERS       = {async-executer, deploy-config, resource, system-uptime, timer}

global.add-bundled-module {yapps_utils: require \./helpers/utils}

ERR_EXIT = (err, message) ->
  ERR err, message
  return process.exit 1


FIND_NAME = (filename) ->
  tokens = filename.split path.sep
  return tokens[tokens.length - 2]


CREATE_APPLICATION = (type, opts) ->
  {name} = module
  CLAZZ = if \base == type then require \./classes/BaseApp else require \./classes/WebApp
  return ERR_EXIT "the class[#{type}] of application is empty-ized" unless CLAZZ?
  try
    DBG "create #{type} with options: #{(JSON.stringify opts).green}"
    return new CLAZZ name, opts, HELPERS
  catch error
    return ERR_EXIT error, "failed to create application #{type.yellow}"


module.exports = exports =

  init: (app_filename) ->
    name = module.name = FIND_NAME app_filename
    INFO "application name: #{name.yellow}"

  create-app: (type, opts) ->
    app_type = \base
    app_opts = {}
    if type?
      if \string == typeof type
        app_type = type
        app_opts = opts
      else if \object == typeof type
        app_opts = type
    return CREATE_APPLICATION app_type, app_opts
