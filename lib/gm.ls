require! <[colors]>

class GlobalModule
  (@opts) ->
    @modules = colors: colors

  add-module: (xs) ->
    self = @
    for k, v of xs
      self.modules[k] = v

global.gm = module.exports = exports = new GlobalModule {}
global.get-bundled-modules = -> return global.gm.modules
global.add-bundled-module = (xs) -> return global.gm.add-module xs

lodash_merge = require \lodash/merge
lodash_find = require \lodash/find
lodash_findIndex = require \lodash/findIndex
lodash_sum = require \lodash/sum
lodash_padStart = require \lodash/padStart
lodash_padEnd = require \lodash/padEnd
global.add-bundled-module {lodash_merge, lodash_find, lodash_findIndex, lodash_sum, lodash_padStart, lodash_padEnd}
