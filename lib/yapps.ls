require \source-map-support .install!

if not String.prototype.starts-with?
  String.prototype.starts-with = (search-string) -> return 0 == this.index-of search-string

module.exports = exports =
  init: (app-filename) ->
    require \yap-require-hook .install!
    require \yap-simple-logger .init app-filename, __filename

