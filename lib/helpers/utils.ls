require! <[mkdirp async colors prettyjson]>
{DBG, WARN} = global.get-logger __filename


CREATE_DIR_ASYNC = (dir, done) ->
  DBG "creating #{dir} ..."
  return mkdirp dir, done

##
# Consider to deprecate ..., no one is using it.
#
#   $ find . -name '*.ls' | xargs -I{} sh -c "grep -H create-directories {}"
#
CREATE_DIRECTORIES = (dirs, done) ->
  return async.eachSeries dirs, CREATE_DIR_ASYNC, done

##
# Consider to deprecate ..., no one is using it.
#
#   $ find . -name '*.ls' | xargs -I{} sh -c "grep -H copy-object {}"
#
copy-object = (dst, src, fields) ->
  for let f, i in fields
    if src[f]?
      dst[f] = src[f]
  return dst


CREATE_BUFFER_WITH_INTS = (ints) ->
  ##
  # https://nodejs.org/docs/latest-v4.x/api/buffer.html#buffer_class_method_buffer_from_array
  # https://nodejs.org/api/buffer.html#buffer_new_buffer_array
  #
  # `new Buffer(array)` is going to be deprecated, so it is better
  # to use `Buffer.from` in newer nodejs versions, at least 4.5+
  #
  return Buffer.from ints if module.node-version >= 4.5
  return new Buffer ints


CREATE_BUFFER_WITH_STRING = (str, encoding=\utf8) ->
  ##
  # https://nodejs.org/docs/latest-v4.x/api/buffer.html#buffer_new_buffer_str_encoding
  # https://nodejs.org/api/buffer.html#buffer_new_buffer_string_encoding
  #
  # `new Buffer(string[, encoding])` is going to be deprecated, so it is better
  # to use `Buffer.from` in newer nodejs versions, at least 4.5+
  #
  return Buffer.from str, encoding if module.node-version >= 4.5
  return new Buffer str, encoding


IS_BUFFER = (b) ->
  return Buffer.isBuffer b


CREATE_BUFFER_WITH_HEX_CHARS = (str) ->
  hexes = str.substring 2


CREATE_BUFFER_WITH_HEXES_SMARTLY = (input) ->
  return CREATE_BUFFER_WITH_INTS input if input instanceof Uint8Array
  return CREATE_BUFFER_WITH_INTS input if input instanceof Uint16Array
  if Array.isArray input
    return CREATE_BUFFER_WITH_INTS [] if input.length is 0
    return CREATE_BUFFER_WITH_INTS input if \number is typeof input[0]
    WARN "CREATE_BUFFER_WITH_HEXES(): input isn't array of octets => #{JSON.stringify input}"
    return null
  else if \string is typeof input
    #
    # Convert the speical hex string `++11223344FEA9` to a binary buffer.
    #
    return CREATE_BUFFER_WITH_STRING (input.substring 2), \hex if /\+\+[0-9,A-Z]*$/ .test input
    return CREATE_BUFFER_WITH_STRING input
  else
    WARN "CREATE_BUFFER_WITH_HEXES(): unexpected input(#{typeof input}) => #{JSON.stringify input}"
    return null



buffer_utils = {
  CREATE_BUFFER_WITH_INTS,
  CREATE_BUFFER_WITH_STRING,
  CREATE_BUFFER_WITH_HEXES_SMARTLY,
  IS_BUFFER
}


COLORIZED = (v) ->
  t = typeof v
  return v.yellow if t is \string
  return v.to-string! .green if t is \number
  return v.to-string! .magenta if t is \boolean and v
  return v.to-string! .red if t is \boolean and not v
  return (JSON.stringify v).blue if t is \object
  return v

PRETTIZE_KVS = (kvs, separator=", ") ->
  xs = [ "#{k.gray}:#{COLORIZED v}" for k, v of kvs ]
  return xs.join separator

PRINT_PRETTY_JSON = (name, config, idents=1, output=console.error) ->
  return output "#{name}: \n#{(JSON.stringify config, null, ' ').gray}" unless prettyjson?
  text = prettyjson.render config, do
    keysColor: \gray
    dashColor: \green
    stringColor: \yellow
    numberColor: \cyan
    defaultIndentation: 4
    inlineArrays: yes
  xs = text.split '\n'
  tabs = "\t" * idents
  output "#{name}:"
  [ output "#{tabs}#{x}" for x in xs ]
  output ""

debug = {COLORIZED, PRETTIZE_KVS, PRINT_PRETTY_JSON}


DataJobQueue = require \./data-job-queue
{SocketServer, SocketConnection, CommandSocketConnection} = sock = require \./sock
classes = {DataJobQueue, SocketServer, SocketConnection, CommandSocketConnection}

module.node-version = parse-float process.version.substring 1
module.exports = exports = {CREATE_DIRECTORIES, buffer_utils, debug, classes}
