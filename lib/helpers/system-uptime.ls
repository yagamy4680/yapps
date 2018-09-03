require! <[fs]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename

const BOOTS_TIMESTAMP_LOGGING_DIR = "/opt/ys/share/timestamp"
const BOOTS_ENV_VARIABLE = "YAPPS_TOE_LINUX_BOOTS"

RET_VALUE = (value, message) ->
  WARN message
  return value


GET_PROCESS_UPTIME = ->
  return Math.floor process.uptime! * 1000ms


GET_SYSTEM_UPTIME = ->
  uptime = GET_PROCESS_UPTIME!
  return RET_VALUE uptime, "using process uptime (#{uptime}ms) as system uptime for mac osx" if process.platform is \darwin
  const SYSFILE = "/proc/uptime"
  try
    buffer = fs.read-file-sync SYSFILE
    return RET_VALUE uptime, "failed to read uptime from #{SYSFILE}, using process uptime (#{uptime}ms) as alternative" unless buffer?
    text = buffer.to-string!
    xs = text.split ' '
    seconds = parse-float xs[0]
    return RET_VALUE uptime, "failed to parse system uptime: #{xs[0]} from #{SYSFILE}, using process uptime (#{uptime}ms) as alternative" if seconds is NaN
    uptime = Math.floor seconds * 1000ms
    INFO "retrieve #{uptime}ms from #{SYSFILE}"
    return uptime
  catch error
    return RET_VALUE uptime, "failed to read system uptime from #{SYSFILE}, using process uptime (#{uptime}ms) as alternative. err: #{error}"


module.system = GET_SYSTEM_UPTIME!


class SystemUptime
  (@opts) ->
    {system} = module
    self = @
    self.boots = 0
    self.app = GET_PROCESS_UPTIME!
    self.system = system
    self.diff = self.system - self.app
    return

  read-boots-from-env: ->
    boots = process.env[BOOTS_ENV_VARIABLE]
    return no unless boots?
    return no if boots is ""
    boots = parse-int boots
    return no if boots is NaN
    @boots = boots
    INFO "detects boots from #{BOOTS_ENV_VARIABLE.yellow}: #{@boots}"
    return yes

  read-boots-from-fs: (done) ->
    self = @
    (err, dirs) <- fs.readdir BOOTS_TIMESTAMP_LOGGING_DIR
    if err?
      dir = "0" # fallback to "0" when running the plugin on non-TOE device, e.g. Mac OS X (developer's machine)
      message = "(fallback to '0' because of err: #{err.to-string! .red})"
    else
      dirs = dirs.sort!
      dir = dirs.pop!
      dir = "0" unless dir?
    self.boots = parse-int dir
    self.boots = 1 if self.boots is 0     # for legacy, because old yapps-scripts still uses `000000` as first-time of boots up.
    self.boots = 0 if self.boots is NaN
    INFO "detect boots from #{BOOTS_TIMESTAMP_LOGGING_DIR.yellow}: #{self.boots} #{message}"
    return done!

  init-boots-var: (done) ->
    return done! if @.read-boots-from-env!
    return @.read-boots-from-fs done

  init: (done) ->
    self = @
    (err) <- @.init-boots-var
    return done err if err?
    INFO "boots: #{self.boots} times"
    INFO "system: #{self.system}ms"
    INFO "app: #{self.app}ms"
    return done!

  synchronize: (ctx) ->
    {boots, app, system, diff} = ctx
    INFO "calibration: boots from #{@boots} to #{boots}"
    INFO "calibration: diff from #{@diff} to #{diff}"
    @boots = boots
    /**
     * Time Calibration Algorithm:
     *
        r-sys = GET_SYSTEM_UPTIME!
        r-app = GET_PROCESS_UPTIME!
        r-diff = r-sys - r-app
        now = GET_PROCESS_UPTIME! + r-diff

        process-uptime-diff = r-app - GET_PROCESS_UPTIME(startup)
        now = GET_PROCESS_UPTIME! + r-app - GET_PROCESS_UPTIME(startup) + (r-sys - r-app)
            = GET_PROCESS_UPTIME! + (r-sys - GET_PROCESS_UPTIME(startup))
     *
     */
    @diff = system - GET_PROCESS_UPTIME!

  to-json: (realtime=no) ->
    {boots, app, system, diff} = @
    app = GET_PROCESS_UPTIME! if realtime
    system = GET_SYSTEM_UPTIME! if realtime
    return {boots, app, system, diff}

  now: ->
    {boots, diff} = self = @
    uptime = GET_PROCESS_UPTIME! + diff
    epoch = (new Date!) - 0
    return {boots, uptime, epoch}


module.exports = exports = SystemUptime
