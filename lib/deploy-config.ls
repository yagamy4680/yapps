require! <[handlebars livescript extendify]>

USE_CURRYING = (environment, variable) -->
  return variable if (typeof variable) in <[string number boolean]>
  return null unless \object is typeof variable
  return variable[environment]


TRANSFORM_INTEGER = (object, dir) ->
  tokens = dir.split "."
  tokens.shift!
  return if tokens.length is 0
  if tokens.length is 1
    k = tokens[0]
    x = object[k]
  else
    k = tokens.pop!
    for y in tokens
      object := object[y]
    x = object[k]
  return object[k] = parse-int x



TRANSFORM_BOOLEAN = (object, dir) ->
  tokens = dir.split "."
  tokens.shift!
  return if tokens.length is 0
  if tokens.length is 1
    k = tokens[0]
    x = object[k]
  else
    k = tokens.pop!
    for y in tokens
      object := object[y]
    x = object[k]
  return object[k] = x == \true


TRANSFORM = (env, json, text, context) ->
  ext = extendify!
  use = USE_CURRYING env
  handlebars.registerHelper \use, use
  try
    {_metadata, _definitions} = json
    ctx = {}
    ctx = ext ctx, _definitions
    ctx = ext ctx, context
    # console.log "text = #{text}"
    # console.log "ctx = #{JSON.stringify ctx}"
    template = handlebars.compile text
    result = template ctx
    # console.log "result = #{result}"
    data = livescript.compile result, json: yes
    output = JSON.parse data
    # console.log "output1 = #{JSON.stringify output}"
    {transforms} = _metadata if _metadata?
    delete output["_metadata"]
    delete output["_definitions"]
    [ TRANSFORM_INTEGER output, x for x in transforms.integers ] if transforms? and transforms.integers?
    [ TRANSFORM_BOOLEAN output, x for x in transforms.booleans ] if transforms? and transforms.booleans?
    return output: output, error: null
  catch error
    return error: error


module.exports = exports = TRANSFORM

