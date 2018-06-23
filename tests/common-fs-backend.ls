require! <[fs path mkdirp]>
{DBG, ERR, WARN, INFO} = global.get-logger __filename
lodash_padStart = require \lodash/padStart

const ROOT_DIR = "/tmp/queues"

const REGEXP_JSON = /[0-9]{4}\-[0-9A-F]{10}\-[0-9]{13}\.json/
const REGEXP_JSON_GZ = /[0-9]{4}\-[0-9A-F]{10}\-[0-9]{13}\.json.gz/


COMPOSE_FILEPATH = (name, format, timestamp) ->
  {boots, uptime, epoch} = timestamp
  {rootdir} = module
  bs = lodash_padStart (boots.toString!), 5, '0'
  up = lodash_padStart (uptime.toString 16 .to-upper-case!), 10, '0'
  # return "#{rootdir}#{path.sep}#{boots}-#{uptime}-#{epoch}.#{format}"
  return "#{rootdir}#{path.sep}#{bs}-#{up}-#{epoch}.#{format}"

DECOMPOSE_FILEPATH = (p, format) ->
  name = path.basename p, ".#{format}"
  [boots, uptime, epoch] = tokens = name.split '-'
  boots = parse-int boots
  uptime = parse-int uptime, 16
  epoch = parse-int epoch
  # tokens = [ (parse-int x) for x in tokens ]
  # [boots, uptime, epoch] = tokens
  return {boots, uptime, epoch}


init = (name, format, done) ->
  module.rootdir = r = "#{ROOT_DIR}/#{name}"
  INFO "initialize #{r} ..."
  return mkdirp r, done

check = (name, format, timestamp) ->
  return done!

write = (name, format, timestamp, buffer=null, done=null) ->
  return path.basename (COMPOSE_FILEPATH name, format, timestamp), ".#{format}" unless buffer? and done?
  f = -> return fs.writeFile (COMPOSE_FILEPATH name, format, timestamp), buffer, done
  setTimeout f, 3000ms

read = (name, format, timestamp, done) ->
  return fs.readFile (COMPOSE_FILEPATH name, format, timestamp), done

remove = (name, format, timestamp, done) ->
  return fs.unlink (COMPOSE_FILEPATH name, format, timestamp), done

list = (name, format, done) ->
  {rootdir} = module
  REGEXP = if format is \json then REGEXP_JSON else REGEXP_JSON_GZ
  (err, files) <- fs.readdir rootdir
  return done err if err?
  INFO "files => #{JSON.stringify files}"
  xs = [ (DECOMPOSE_FILEPATH f, format) for f in files when REGEXP.test f ]
  return done null, xs

module.exports = exports = {init, check, write, read, remove, list}