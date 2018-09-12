#
# Simple Logger
#
require! <[path]>
require! <[colors moment]>

const PADDINGS = [""] ++ [ ([ ' ' for y from 1 to x ]).join '' for x from 1 to 28 ]

const LEVELS =
  info : {string: 'INFO'.green }
  debug: {string: 'DBG '.blue  }
  error: {string: 'ERR '.red   }
  warn : {string: 'WARN'.yellow}


class ConsoleDriver
  (@manager, @name, precise) ->
    @timefmt = 'MM/DD HH:mm:ss'
    @timefmt = 'MM/DD HH:mm:ss.SSS' if precise? and precise
    len = name.length
    padding = if len <= 28 then PADDINGS[28 - len] else ""
    @formatted-name = "#{name}#{padding}"

  log: (lv, err, message) ->
    {manager, timefmt, formatted-name} = self = @
    msg = if message? then message else err
    level = LEVELS[lv]
    now = moment! .format timefmt
    prefix = "#{now.gray} #{formatted-name} [#{level.string}]"
    if message?
      if err? and err.stack?
        console.error "#{prefix} #{err.stack}"
        console.error "#{prefix} #{msg}"
      else
        exx = "#{err}"
        console.error "#{prefix} err: #{exx.red} => #{msg}"
    else
      console.error "#{prefix} #{msg}"

  error: (err, message) -> return @.log \error, err, message
  info : (err, message) -> return @.log \info , err, message
  warn : (err, message) -> return @.log \warn , err, message
  debug: (err, message) -> return @.log \debug, err, message



class Logger
  (@manager, @module-name, @base-name, @verbose=no, precise-timestamp=no) ->
    @name = name = if base-name? and base-name != module-name then "#{module-name}::#{base-name}" else "#{module-name}"
    @driver = new ConsoleDriver manager, name, precise-timestamp

  set-verbose: (@verbose) -> return
  debug: -> return @driver.debug.apply @driver, arguments if @verbose
  info : -> return @driver.info.apply  @driver, arguments
  warn : -> return @driver.warn.apply  @driver, arguments
  error: -> return @driver.error.apply @driver, arguments


class LoggerManager
  (@app-filename, @yap-filename, @verbose=no) ->
    @app-dirname = path.dirname app-filename
    tokens = yap-filename.split path.sep
    tokens.pop!
    tokens.pop!
    tokens.pop!
    @y-module-dir = ymd = tokens.join path.sep
    console.error "[logger] y-module-dir = #{ymd}"
    @precise-timestamp = process.env[\YAPPS_LOGGER_PRECISE_TIMESTAMP] is \true
    @loggers = []
    @logger-map = {}

  parse-filename: (filename) ->
    {app-dirname, app-filename, y-module-dir} = self = @
    ext-name = path.extname filename
    base-name = path.basename filename, ext-name
    return name: \__app__, basename: null if filename is app-filename
    if filename.starts-with app-dirname
      filename = filename.substring app-dirname.length
      tokens = filename.split path.sep
      if tokens.length == 2
        # E.g. /apps/sensor-web/test.ls    => name: '__test__'
        return name: "__#{base-name}__", basename: null
      else if tokens.length == 3
        # E.g. /apps/sensor-web/lib/xyz.ls => name: 'xyz'
        return name: base-name, basename: null
      else if tokens.length == 4
        # E.g. /apps/sensor-web/lib/def/good.ls => name: 'def', basename: 'good'
        return name: tokens[2], basename: base-name
      else
        # E.g. /apps/sensor-web/lib/foo/bar/great.ls => name: 'bar', basename: 'great'
        return name: "...#{tokens[tokens.length - 2]}", basename: base-name
    else
      if y-module-dir? and filename.starts-with y-module-dir
        filename = filename.substring y-module-dir.length
        tokens = filename.split path.sep
        # E.g. /externals/y-modules/sensorhub-client/lib/sensorhub-client.ls => name: 'sensorhub-client'
        return name: tokens[1], basename: null if tokens[1] == base-name
        # E.g. /externals/y-modules/yapps/lib/classes/web/index.ls => name: 'yapps', basename: 'web'
        return name: tokens[1], basename: tokens[tokens.length - 2] if \index == base-name
        # E.g. /externals/y-modules/sensorhub-client/lib/helper.ls => name: 'sensorhub-client', basename: 'helper'
        return name: tokens[1], basename: base-name
      else
        # E.g. /externals/yapps-plugins/communicator/lib/tcp.ls => name: 'communicator', basename: 'tcp'
        idx = filename.index-of '/yapps-plugins/'
        # E.g. /profiles/[xxx]/plugins/echonet-lite-service/index.ls => name: 'echonet-lite-service', basename: 'index'
        # E.g. /plugins/system-helpers/lib/regular-gc.ls             => name: 'system-helpers', basename: 'regular-gc'
        idx = filename.index-of '/plugins/' if idx < 0
        return name: "??", basename: base-name if idx < 0
        tokens = filename.substring idx .split path.sep
        return name: tokens[2], basename: base-name

  create-logger: (filename) ->
    {loggers, logger-map, precise-timestamp, verbose} = self = @
    {name, basename} = self.parse-filename filename
    logger = new Logger self, name, basename, verbose, precise-timestamp
    logger-name = logger.name
    loggers.push logger
    logger-map[logger-name] = logger
    get = (logger, level) -> return -> logger[level].apply logger, arguments
    DBG = get logger, \debug
    ERR = get logger, \error
    WARN = get logger, \warn
    INFO = get logger, \info
    return {DBG, ERR, WARN, INFO}

  get-logger-names: ->
    {logger-map} = self = @
    xs = [ k for k, v of logger-map ]
    return xs

  set-logger-verbose: (name=null, verbose=no) ->
    {logger-map, loggers} = self = @
    # console.log "set-logger-verbose(#{name}, #{verbose})"
    if name?
      logger = logger-map[name]
      logger.set-verbose verbose if logger?
    else
      [ (l.set-verbose verbose) for l in loggers ]


module.exports = exports =
  init: (app-filename, yap-filename, verbose) ->
    module.manager = global.LOG = new LoggerManager app-filename, yap-filename, verbose
    return

global.get-logger = (filename) -> return module.manager.create-logger filename

