require! <[mkdirp async]>
{DBG} = global.get-logger __filename


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




# module.exports = exports = {create-directories, copy-object}

module.exports = exports = {CREATE_DIRECTORIES}