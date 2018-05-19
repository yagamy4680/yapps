require! <[async colors uid]>
{DBG} = global.get-logger __filename
global.add-bundled-module {async, uid}

loggerCurrying = (executor, task_name, logger, message) -->
  # prefix = "[#{colors.gray executor.type}.#{colors.gray executor.id}.#{colors.gray task_name}]"
  # prefix = "#{executor.type}#{colors.gray '.'}#{executor.id}#{colors.gray '.'}#{task_name}"
  num = "#{executor.num}"
  id = "#{executor.id}:#{num.blue}"
  prefix = "#{executor.type}[#{id.gray}].#{task_name.gray}"
  text = "#{prefix} #{message}"
  return logger text if logger?
  return console.log text


runTaskCurrying = (executor, context, logger, task_name, func, cb) -->
  DBG = loggerCurrying executor, task_name, logger
  try
    func executor, context, DBG, (err, result) -> return cb err, result
  catch error
    DBG "#{error.stack.red}"
    return cb error, null


seriesEndCurrying = (executor, cb, err, results) --> return cb executor, executor.context, err, results



module.exports = exports = class AsyncExecuter
  (@options) ->
    {type, logger, context, id} = options if options?
    @context = if context? then context else {}
    @type = if type? then type else "unknown"
    @logger = if logger? then logger else console.log
    @id = if id? then id else uid!
    @num = 0


  series: (tasks, callback) ->
    {context, logger, num} = self = @
    self.num = num + 1
    new_funcs = [ (runTaskCurrying self, context, logger, t.name, t.func) for let t, i in tasks ]
    end = seriesEndCurrying self, callback
    return async.series new_funcs, end

