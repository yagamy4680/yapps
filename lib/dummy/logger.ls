require! <[path colors moment]>

PADDINGS = [(' ' * i) for i from 1 to 20]

ADD_PADDINGS = (str, left=yes) ->
  total = 26
  len = str.length
  paddings = if len >= total then "" else PADDINGS[total - len]
  return if left then paddings + str else str + paddings

LOGGER = (severity, name, message) -->
  return console.log "#{moment! .format 'HH:mm:ss:SSS'} #{ADD_PADDINGS name, no} [#{severity}]: #{message}" if message?

global.get-logger = (name) ->
  basename = path.basename name
  DBG  = LOGGER ('DBG '.gray  ), basename
  ERR  = LOGGER ('ERR '.red   ), basename
  WARN = LOGGER (\WARN .yellow), basename
  INFO = LOGGER (\INFO .blue  ), basename
  return {DBG, ERR, WARN, INFO}
