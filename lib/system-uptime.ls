require! <[fs]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename


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
    self.app = GET_PROCESS_UPTIME!
    self.system = system
    self.diff = self.system - self.app
    self.boots = 0  # [todo] read `boots` from environment variable or timestamp logging dir: /opt/ys/share/timestamp
    INFO "boots: #{self.boots}ms"
    INFO "system: #{self.system}ms"
    INFO "app: #{self.app}ms"
    return

  now: ->
    {boots, diff} = self = @
    uptime = GET_PROCESS_UPTIME! + diff
    epoch = (new Date!) - 0
    return {boots, uptime, epoch}


module.exports = exports = SystemUptime
