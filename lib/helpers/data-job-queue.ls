require! <[path async]>

{DBG, ERR, WARN, INFO} = global.get-logger __filename
{lodash_merge, lodash_sortBy, lodash_findIndex, lodash_padStart, async} = global.get-bundled-modules!

GET_PROCESS_UPTIME = ->
  return Math.floor process.uptime! * 1000ms

APPLY_CONDITIONALLY = (func, data, done) ->
  return done data unless func?
  return func data, done

ERR_DONE = (done, err, message) ->
    ERR err, message
    return done!

DONE_WITH_SELF = (self, done=null, err=null, message=null) ->
  ERR err, message if err? and message?
  done! if done? and \function is typeof done
  return self

FINALIZE_DATA_JOB = (job, done) ->
  return job.store done


const DEFAULT_OPTS =
  verbose: no
  intervals:
    check: 500ms
    consume: 3000ms
    store: 10s * 1000ms    # when a job enqueues more than `store` interval, but not processing (consuming), then tries to write it to backend storage e.g. disk.
  job:
    data_format: \json.gz
    serializer: null
  consumer: null
  backend:
    init: null
    check: null           # optional, to be called before writing data
    write: null
    read: null
    remove: null
    list: null

class DataJob
  (@parent, @timestamp=null, @data=null, @serialized=no) ->
    {consumer} = @parent
    now = @parent.uptime.now!
    @timestamp = now unless @timestamp?
    {boots, uptime, epoch} = @timestamp
    @boots = boots
    @uptime = uptime
    @epoch = epoch
    @created_at = now.uptime
    @buffer = null
    @consumer = consumer
    @consuming = no
    @consumed = no
    @writing = no
    {name, format} = parent
    ts = parent.backend_write name, format, @timestamp, null, null
    @ts = ts = if ts? and \string is typeof ts then ts else "#{boots}-#{uptime}-#{epoch}"
    @prefix = "#{parent.prefix}[#{ts.green}]"
    @retries = 0

  load: (done) ->
    {parent, prefix, timestamp, data} = self = @
    {name, format, opts} = parent
    return done null, data if data?
    start0 = (new Date!) - 0
    (read-err, buffer) <- parent.backend_read name, format, timestamp
    duration = "#{(new Date!) - start0}"
    return done read-err if read-err?
    self.dbg "#{prefix}: load #{buffer.length} bytes from backend storage with #{duration.cyan}ms"
    start1 = (new Date!) - 0
    (d-err, data) <- APPLY_CONDITIONALLY opts.job.deserializer, buffer
    duration = "#{(new Date!) - start1}"
    return done d-err if d-err?
    self.dbg "#{prefix}: deserialize #{buffer.length} bytes to data object with #{duration.cyan}ms"
    self.data = data
    return done null, data

  consume: (done) ->
    {parent, consumer, prefix, timestamp, data, retries} = self = @
    {name, format} = parent
    self.dbg "#{prefix}: start consumption (retries = #{retries})"
    self.consuming = yes
    (load-err, data) <- self.load
    self.consuming = no
    return ERR_DONE done, load-err, "#{prefix}: failed to load from disk (or deserialize) => drop from data queue." if load-err?
    start1 = (new Date!) - 0
    self.consuming = yes
    (err) <- consumer name, format, timestamp, data, retries
    self.consuming = no
    self.consumed = yes
    duration = "#{(new Date!) - start1}"
    self.dbg "#{prefix}: end consumption (total #{duration.cyan}ms)"
    return done! unless err?
    self.consumed = no
    if \string is typeof err
      ERR "#{prefix}: end consumption with error => #{err.red}" if parent.verbose
    else
      ERR err, "#{prefix}: end consumption with error" if parent.verbose
    self.retries = self.retries + 1
    return done err

  dbg: (message) ->
    DBG message if @parent.verbose
    return @

  store: (done=null) ->
    {parent, prefix, timestamp, serialized, data} = self = @
    return DONE_WITH_SELF self, done if serialized
    {name, format, opts} = parent
    self.writing = yes
    APPLY_CONDITIONALLY opts.job.serializer, data, (s-err, buffer) ->
      self.writing = no
      return DONE_WITH_SELF self, done, s-err, "#{prefix}: serialize data but error" if s-err?
      start = (new Date!) - 0
      self.writing = yes
      parent.backend_write name, format, timestamp, buffer, (write-err) ->
        self.writing = no
        duration = "#{(new Date!) - start}"
        self.dbg "#{prefix}: store #{buffer.length} bytes with #{duration.cyan}ms"
        self.serialized = yes
        return DONE_WITH_SELF self, done, write-err, "#{prefix}: store #{buffer.length} bytes but err" if write-err?
        return DONE_WITH_SELF self, done
    return self

  cleanup: ->
    {parent, prefix, timestamp, serialized, created_at} = self = @
    now = parent.uptime.now!
    lifetime = "#{now.uptime - created_at}"
    return self.dbg "#{prefix}: no need for cleanup, total lifetime #{lifetime.magenta}ms" unless serialized
    {name, format} = parent
    start = (new Date!) - 0
    parent.backend_remove name, format, timestamp, (err) ->
      duration = "#{(new Date!) - start}"
      self.dbg "#{prefix}: clean-up takes #{duration.cyan}ms"
      return unless err?
      return ERR err, "#{prefix}: clean-up but error"
    return self

  get-job-state: ->
    {ts} = self = @
    W = \W .magenta
    W = '.' unless @writing
    S = \S .yellow
    S = '.' unless @serialized
    D = \D .green
    D = '.' unless @data?
    xs = [D, S, W]
    xs = ["."] * xs.length if self.consumed
    color = \white
    color = \gray unless self.data?
    color = \magenta if self.writing
    color = \red if self.consumed
    ts = ts[color]
    ci = "consuming" .cyan
    return if self.consuming then "[#{xs.join ''}] #{ts} (#{ci})" else "[#{xs.join ''}] #{ts}"

  check-persistence: ->
    return if @serialized or @writing or @consuming
    {boots, uptime, epoch} = @parent.uptime.now!
    duration = uptime - @uptime
    return @.store! if duration > @parent.opts.intervals.store

  at-check: (interval) ->
    return if @consumed
    @.check-persistence!


class DataJobQueue
  (@name, @uptime, opts) ->
    @prefix = "queue[#{name.yellow}]"
    @opts = lodash_merge {}, DEFAULT_OPTS, opts
    @queue = []
    @finished-jobs = []
    {verbose, job, intervals} = @opts
    @verbose = if \boolean is typeof verbose then verbose else no
    @format = job.data_format
    @check-timer = null
    @check-interval = intervals.check
    @consuming = no
    @consume-timeout = intervals.consume

  dump-existed-jobs: (forced=no) ->
    {verbose, prefix, queue} = self = @
    return unless verbose and not forced
    return INFO "#{prefix}: existing jobs: 0" if queue.length is 0
    INFO "#{prefix}: existing jobs:"
    xs = lodash_sortBy @finished-jobs, <[boots uptime epoch]>
    ys = [ (x.get-job-state!) for x in xs ]
    [ console.log "\t#{y}" for y in ys ]
    xs = lodash_sortBy @queue, <[boots uptime epoch]>
    ys = [ (x.get-job-state!) for x in xs ]
    [ console.log "\t#{y}" for y in ys ]

  init: (done) ->
    {prefix, name, opts} = self = @
    {consumer, backend, job, intervals} = opts
    {init, check} = backend
    return done "#{prefix}: missing consumer function" unless consumer?
    return done "#{prefix}: expect consumer function but #{typeof consumer}" unless \function is typeof consumer
    self.consumer = consumer
    f = (name, cb) ->
      func = backend[name]
      return cb "#{prefix}: missing backend.#{name}() function" unless func?
      return cb "#{prefix}: expects backend.#{name} as function, but #{typeof func}" unless \function is typeof func
      self["backend_#{name}"] = func
      return cb!
    (verify-err) <- async.eachSeries <[init write read remove list check]>, f
    return done verify-err if verify-err?
    format = job.data_format
    (bkend-init-err) <- backend.init name, format
    return done bkend-init-err if bkend-init-err?
    (bkend-list-err, timestamps) <- backend.list name, format
    return done bkend-list-err if bkend-list-err?
    self.queue = [ (new DataJob self, t, null, yes) for t in timestamps ]
    self.dump-existed-jobs yes
    t = -> return self.at-check self.check-interval
    self.check-timer = setInterval t, self.check-interval
    INFO "#{prefix}: initiate a regular check timer with #{self.check-interval}ms"
    return done!

  fini: (done) ->
    {queue} = self = @
    return async.eachSeries queue, FINALIZE_DATA_JOB, done

  consume-job: ->
    {prefix, name, format, queue, consumer, consuming, verbose} = self = @
    return unless queue.length > 0
    return if consuming
    self.dump-existed-jobs!
    xs = lodash_sortBy queue, <[boots uptime epoch]>
    idx = lodash_findIndex xs, (x) -> return (not x.consuming) and (not x.writing)
    return WARN "#{prefix}: all jobs are busy in either consuming or writing" if idx is -1
    [j] = xs.splice idx, 1
    INFO "#{prefix}: select jobs[#{idx}] => #{j.ts.green}" if verbose
    return WARN "#{prefix}: all jobs are busy in either consuming or writing" if j.consuming or j.writing
    self.queue = xs
    self.consuming = yes
    (err) <- j.consume
    self.consuming = no
    return self.cleanup j unless err?
    return self.queue.push (j.store!)

  cleanup: (j) ->
    {finished-jobs} = self = @
    finished-jobs.shift! if finished-jobs.length > 10
    finished-jobs.push j
    j.cleanup!

  enqueue: (data) ->
    {queue} = self = @
    j = new DataJob self, null, data
    queue.push j
    return unless queue.length is 1
    f = -> return self.consume-job!
    return process.nextTick f

  check-consumer-timeout: (interval) ->
    {consuming, opts} = self = @
    return if consuming
    self.consume-timeout = self.consume-timeout - interval
    {consume-timeout} = self
    return if consume-timeout > 0
    self.consume-timeout = opts.intervals.consume
    return self.consume-job!

  check-persistence: (interval) ->
    {queue} = self = @
    [ (q.at-check interval) for q in queue ]

  at-check: (interval) ->
    @.check-consumer-timeout interval
    @.check-persistence interval
    return

  get-size: ->
    return @queue.length


module.exports = exports = DataJobQueue
