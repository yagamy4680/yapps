# Resource module.
#
#   - auto detect work_dir with following search order
#
#     1. $WORK_DIR/config       => process.env['WORK_DIR']
#     2. ./config               => path.resolve('.')
#     3. $(dirname $0)/config   => path.dirname(process.argv[1])
#
#
require! <[fs path colors]>
{DBG, ERR} = global.get-logger __filename

settings =
  program_name: null
  app_dir: null
  work_dir: null
  config_dir: null

CHECK = (p) ->
  config_dir = path.resolve "#{p}#{path.sep}config"
  log_dir = path.resolve "#{p}#{path.sep}logs"
  DBG "checking #{path.resolve p}"
  try
    dirs = fs.readdirSync config_dir
    if not fs.existsSync log_dir then fs.mkdirSync log_dir
    settings.work_dir = path.resolve p
    settings.config_dir = config_dir
    DBG "use #{settings.work_dir.cyan} as work_dir"
    DBG "use #{settings.app_dir.cyan} as app_dir"
  catch error
    DBG "checking #{path.resolve p} but failed"

argv = [ x for x in process.argv ]
[a1, a2] = argv
a1 = path.basename a1 if a1?
a2 = path.basename a2 if a2?
entry = if a1? and a2? and a1 is \node and a2 is \lsc then argv[2] else argv[1]

# Setup the default program name.
#
settings.program_name = \unknown
settings.program_name = path.basename entry if entry?

# Setup the default app directory.
#
settings.app_dir = process.cwd!
settings.app_dir = path.resolve path.dirname entry if entry?


# 1.Check process.env['WORK_DIR'] can be used as work_dir
#
CHECK process.env['WORK_DIR'] if process.env['WORK_DIR']?

# 2. Check current dir.
#
CHECK path.resolve "." unless settings.work_dir?

# 3. Check process.argv[1] can be used as work_dir
#
# typically, the process.argv are as follows when executing `~/Downloads/test0.ls`
#   argv[0] = /opt/boxen/nodenv/versions/v0.10/bin/lsc
#   argv[1] = /Users/yagamy/Downloads/test0.ls
#
#   ["node","/Users/yagamy/Works/workspaces/t2t/yapps-tt/tests/test02/index.js"]
#
CHECK path.dirname entry if not settings.work_dir and entry?

# If there is still no work_dir available to use, then terminate
# the current process immediately with error exit code.
#
if not settings.work_dir?
  ERR "failed to find any work directory."
  if not process.env.VERBOSE? then ERR "please re-run the program with environment variable VERBOSE=true to get further verbose messages..."
  process.exit 1



LOAD_CONFIG = (p, callback) ->
  found = false
  try
    config = if p.json then JSON.parse fs.readFileSync p.path else require p.path
    found = true
    callback null, config
  catch error
    DBG "failed to load #{p.path} due to error: #{error}"
  return found


resource =

  /**
   * Dump all enviroment variables
   */
  dumpEnvs: ->
    for let v, i in process.argv
      DBG "argv[#{i}] = #{v}"
    DBG "process.execPath = #{process.execPath}"
    DBG "process.arch = #{process.arch}"
    DBG "process.platform = #{process.platform}"
    DBG "process.cwd() = #{process.cwd!}"
    DBG "path.normalize('.') = #{path.normalize '.'}"
    DBG "path.normalize(__dirname) = #{path.normalize __dirname}"
    DBG "path.resolve('.') = #{path.resolve '.'}"
    DBG "path.resolve(__dirname) = #{path.resolve __dirname}"

  /**
   * Load configuration file from following files in order
   *   - ${config_dir}/${name}.ls
   *   - ${config_dir}/${name}.json
   *
   * @param name, the name of configuration file to be loaded.
   */
  loadConfig: (name, callback) ->
    config-ls = "#{settings.config_dir}#{path.sep}#{name}.ls"
    config-json = "#{settings.config_dir}#{path.sep}#{name}.json"
    try
      text = "#{fs.readFileSync config-ls}"
      text = require \livescript .compile text, json: yes
      json = JSON.parse text
      return json: json, text: text, source: yes
    catch error
      DBG "failed to load #{config-ls}, err: #{error}"

    try
      text = "#{fs.readFileSync config-json}"
      json = JSON.parse text
      return json: json, text: text, source: no
    catch error
      DBG "failed to load #{config-json}, err: #{error}"
      return null

    /*
    pathes =
      * path: "#{settings.config_dir}#{path.sep}#{name}.ls"
        json: false
      * path: "#{settings.config_dir}#{path.sep}#{name}.json"
        json: true

    ret = found: no, config: null

    for p in pathes
      continue if ret.found
      try
        DBG "try #{p.path} ..."
        text = "#{fs.readFileSync p.path}"
        text = require \livescript .compile text, json: yes unless p.json
        ret.config = JSON.parse text
        ret.found = yes
      catch error
        DBG "stack: #{error.stack}"
        continue

    DBG "cannot find config #{name}" unless ret.found
    return ret.config
    */



  /**
   * Resolve to an absolute path to the file in the specified
   * `type` directory, related to work_dir.
   *
   * @param type, the type of directory, e.g. 'logs', 'scripts', ...
   * @param filename, the name of that file.
   */
  resolveWorkPath: (type, filename) ->
    return path.resolve "#{settings.work_dir}#{path.sep}#{type}#{path.sep}#{filename}"


  /**
   * Resolve to an absolute path to the file in the specified
   * `type` directory, related to app_dir.
   *
   * @param type, the type of directory, e.g. 'logs', 'scripts', ...
   * @param filename, the name of that file.
   */
  resolveResourcePath: (type, filename) ->
    ret = path.resolve "#{settings.app_dir}#{path.sep}#{type}#{path.sep}#{filename}"
    # DBG "#{settings.app_dir}, #{type}, #{filename}, #{ret}"
    return ret

  /**
   * Load javascript, livescript, or coffeescript from ${app_dir}/lib. For example,
   * when `loadScript 'foo'` is called, the function tries to load scripts one-by-one
   * as following order:
   *
   *    1. ${app_dir}/lib/foo.js
   *    2. ${app_dir}/lib/foo.ls
   *
   * @name {[type]}
   */
  loadScript: (name) ->
    return require "#{settings.app_dir}#{path.sep}lib#{path.sep}#{name}"

  /**
   * Load javascript, livescript, or coffeescript from ${app_dir}/lib/plugins. For example,
   * when `loadPlugin 'foo'` is called, the function tries to load scripts one-by-one
   * as following order:
   *
   *    1. ${app_dir}/lib/plugins/foo.js
   *    2. ${app_dir}/lib/plugins/foo.ls
   *    3. ${app_dir}/lib/plugins/foo/index.js
   *    4. ${app_dir}/lib/plugins/foo/index.ls
   *    5. ${esys_modules}/base/lib/plugins/foo.js
   *    6. ${esys_modules}/base/lib/plugins/foo.ls
   *    7. ${esys_modules}/base/lib/plugins/foo/index.js
   *    8. ${esys_modules}/base/lib/plugins/foo/index.ls
   *
   * @name {[type]}
   */
  loadPlugin: (name) ->
    lib = \lib
    plugins = \plugins
    errors = []
    pathes =
      * "#{settings.app_dir}#{path.sep}#{lib}#{path.sep}#{plugins}#{path.sep}#{name}"
      * "#{settings.app_dir}#{path.sep}#{lib}#{path.sep}#{plugins}#{path.sep}#{name}#{path.sep}index"
      * "#{__dirname}#{path.sep}#{plugins}#{path.sep}#{name}"
      * "#{__dirname}#{path.sep}#{plugins}#{path.sep}#{name}#{path.sep}index"

    found = no
    m = null

    for let p, i in pathes
      if not found
        try
          m := require p
          found := yes
        catch error
          exx = err: error, path: p
          errors.push exx

    return m if found

    for let exx, i in errors
      DBG "loading #{exx.path} but err: #{exx.err}"

    exx = errors.pop!
    throw exx.err


  /**
   * Get the program name of entry javascript (livescript) for
   * nodejs to execute.
   */
  getProgramName: -> return settings.program_name

  getAppDir: -> return settings.app_dir
  getWorkDir: -> return settings.work_dir

module.exports = exports = resource