require \source-map-support .install!
require \yap-require-hook .install!
require \./helpers/gm

PRINT_HELP = (opt) ->
  opt.showHelp!
  process.exit 0

module.exports = exports =
  init: (app_filename) ->
    opt = (require \optimist).usage 'Usage: $0'
      .alias    \c, \config
      .describe \c, 'the name of deployment configuration, e.g. production, development, testing...'
      .default  \c, \default
      .alias    \p, \pidfile
      .describe \p, 'PID file'
      .default  \p, null
      .alias    \u, \unixsock
      .describe \u, ''
      .default  \u, null
      .alias    \d, \deployment
      .describe \d, 'deployment mode or not'
      .default  \d, no
      .alias    \v, \verbose
      .describe \v, 'verbose message output (level is changed to `debug`)'
      .default  \v, false
      .alias    \q, \quiet
      .describe \q, 'disable logging outputs to local file, but still outputs to stderr'
      .default  \q, false
      .alias    \b, 'config_bool'
      .describe \b, 'overwrite a configuration with boolean value, e.g. -b "system.influxServer.secure=false"'
      .alias    \s, 'config_string'
      .describe \s, 'overwrite a configuration with string value, e.g. -s "system.influxServer.user=smith"'
      .alias    \i, 'config_int'
      .describe \i, 'overwrite a configuration with int value, e.g. -i "behavior.notify.influxPeriod=3000"'
      .alias    \a, 'config_str_array'
      .describe \a, 'overwrite a configuration with array of strings with delimiter character `COMMA`, e.g. -a "system.influxServer.clusters=aa.test.net,bb.test.net,cc.test.net"'
      .alias    \o, 'config_object'
      .describe \o, 'overwrite a configuration with json object string, e.g. -o "system.influxServer.connections.ifdb999={"url":"tcp://192.168.1.110:6020","enabled":false}"'
      .boolean <[h v q]>
    {verbose, help} = argv = global.argv = opt.argv
    PRINT_HELP opt if help
    logger = require \./logger
    logger.init app_filename, __filename, verbose
    inner = module.inner = require \./inner
    inner.init app_filename

  create-app: (type, opts) ->
    return module.inner.create-app type, opts
