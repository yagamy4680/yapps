require \source-map-support .install!
require \yap-require-hook .install!
require! <[colors]>

if not String.prototype.starts-with?
  String.prototype.starts-with = (search-string) -> return 0 == this.index-of search-string

if not String.prototype.ends-with?
  String.prototype.ends-with = (str) -> return str == this.substring this.length - str.length, this.length

class GlobalModule
  (@opts) ->
    @modules = colors: colors

  add-module: (xs) ->
    self = @
    for k, v of xs
      self.modules[k] = v

global.gm = new GlobalModule {}
global.get-bundled-modules = -> return global.gm.modules
global.add-bundled-module = (xs) -> return global.gm.add-module xs

lodash_merge = require \lodash/merge
lodash_find = require \lodash/find
lodash_findIndex = require \lodash/findIndex
lodash_sum = require \lodash/sum
global.add-bundled-module {lodash_merge, lodash_find, lodash_findIndex, lodash_sum}


module.exports = exports =
  init: (app-filename) ->
    require \yap-simple-logger .init app-filename, __filename
    require \./inner .init app-filename

  create-app: (type, opts) ->
    require \./inner .create-app type, opts
