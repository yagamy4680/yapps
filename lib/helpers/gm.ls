require! <[path fs]>
require! <[colors moment mkdirp prettyjson semver handlebars]>

class GlobalModule
  (@opts) ->
    @modules = {colors}

  add-module: (xs) ->
    self = @
    for k, v of xs
      self.modules[k] = v
    return xs

global.gm = module.exports = exports = new GlobalModule {}
global.get-bundled-modules = -> return global.gm.modules
global.add-bundled-module = (xs) -> return global.gm.add-module xs
global.get-external-module-version = (name) -> return (require "#{name}/package.json").version

lodash_merge = require \lodash/merge
lodash_find = require \lodash/find
lodash_findIndex = require \lodash/findIndex
lodash_sum = require \lodash/sum
lodash_sortBy = require \lodash/sortBy
lodash_padStart = require \lodash/padStart
lodash_padEnd = require \lodash/padEnd
lodash_camelCase = require \lodash/camelCase

yaml_loader = require 'js-yaml/lib/js-yaml/loader'
yaml_safeLoad = yaml_loader.safeLoad
uuid_v1 = require 'uuid/v1'
uuid_v4 = require 'uuid/v4'


class PluginModuleHelper
  (@pmodule) ->
    @ready = no
    return unless pmodule?
    p = null
    p = pmodule.filename unless p?
    p = pmodule.id unless p?
    return unless p?
    @module_dir = p
    @.find-info p

  find-info: (rootdir) ->
    return if rootdir is path.dirname rootdir
    package_json = null
    try
      package_json = require "#{rootdir}/package.json"
    catch error
      return @.find-info path.dirname rootdir
    @rootdir = rootdir
    @package_json = package_json
    @ready = yes

  is-ready: ->
    return @ready

  get-rootdir: ->
    return @rootdir

  get-package-json: ->
    return @package_json

  read-json: (filename) ->
    return ["missing module object reference to initiate rootdir"] unless @ready
    fullpath = "#{@rootdir}/#{filename}"
    try
      json = require fullpath
    catch error
      return ["failed to read #{fullpath}: #{error}"]
    return [null, json]

  read-yaml: (filename) ->
    return ["missing module object reference to initiate rootdir"] unless @ready
    fullpath = "#{@rootdir}/#{filename}"
    buffer = fs.readFileSync "#{fullpath}"
    return ["missing #{fullpath}"] unless buffer?
    yaml = yaml_safeLoad buffer.to-string!
    return ["invalid spec.yaml"] unless yaml?
    return [null, yaml]

create_module_helper = (pmodule) -> return new PluginModuleHelper pmodule





global.add-bundled-module {
  semver,
  lodash_merge, lodash_find, lodash_findIndex, lodash_sum, lodash_sortBy,
  lodash_padStart, lodash_padEnd, lodash_camelCase
  yaml_loader, yaml_safeLoad,
  mkdirp, moment, prettyjson, handlebars
  uuid_v1, uuid_v4,
  create_module_helper
}