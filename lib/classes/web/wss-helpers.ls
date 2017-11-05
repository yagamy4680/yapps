{DBG, ERR, WARN, INFO} = global.get-logger __filename


const INDEX_SEPARATOR = "_"
const TASK_EXPIRATION_PERIOD = 30s

# Request and Response commander's implementation.
#
class RaR_Impl
  (@name, @opts, @context) ->
    self = @
    self.outgoing-tasks = {}      # the pool of tasks that are sent to peer
    self.outgoing-counter = 0
    self.incoming-tasks = {}      # the pool of tasks that are received from peer
    self.incoming-counter = 0
    f = -> self.at-timeout!
    self.timer = setInterval f, 1000ms
    return

  # Clear all resources used in the RaR commander.
  #
  clear: ->
    {timer} = self = @
    clearInterval timer

  # Set the function for sending outgoing packet via REQUEST channel
  #
  set-outgoing-req: (@send-req) -> return

  # Set the function for sending outgoing packet via RESPONSE channel
  #
  set-outgoing-rsp: (@send-rsp) -> return

  # Process the incoming packet from REQUEST channel
  #
  process-incoming-req: (packet) ->
    {name, context, incoming-tasks} = self = @
    {index, action, response, args} = packet
    response = no unless response?
    args = [] unless args?
    text = (JSON.stringify packet).gray
    return WARN "[#{name}] process-request-packet(): missing index => #{text}" unless index?
    return self.response-error index, "missing action => #{text}" unless action?
    return self.response-error index, "invalid args for #{action} => #{text}" unless Array.isArray args
    now = new Date!
    # func-name = "process_request_#{action}"
    # func = context[func-name]
    func = context[action]
    return self.response-error index, "missing handler for action[#{action}]" unless func?
    dummy = (error, result) -> return
    ds = [dummy] ++ args
    return func.apply context, ds unless response
    done = (error, result) -> return self.postprocess-request index, action, args, error, result
    ds = [done] ++ args
    task = packet: packet, start: now, expire: TASK_EXPIRATION_PERIOD, in-or-out: \incoming
    incoming-tasks[index] = task
    return func.apply context, ds

  # Process the incoming packet from RESPONSE channel
  #
  process-incoming-rsp: (packet) ->
    {name, outgoing-tasks} = self = @
    {index, error, result} = packet
    text = (JSON.stringify packet).gray
    return WARN "[#{name}] process-response-packet(): missing index => #{text}" unless index?
    t = outgoing-tasks[index]
    return WARN "[#{name}] tasks[#{index}] => too late since task is deleted" unless t?
    delete outgoing-tasks[index]
    {done} = t
    return done error, result

  response-error: (index, error) ->
    {send-rsp} = self = @
    packet = index: index, result: null, error: error
    return send-rsp packet

  response-okay: (index, result) ->
    {send-rsp} = self = @
    packet = index: index, result: result, error: null
    return send-rsp packet

  postprocess-request: (index, action, args, error, result) ->
    {name, incoming-tasks} = self = @
    t = incoming-tasks[index]
    return WARN "[#{name}] #{action}::#{index} => too late since task is deleted" unless t?
    delete incoming-tasks[index]
    return self.response-error index, error if error?
    return self.response-okay index, result

  get-next-outgoing-counter: ->
    @outgoing-counter = @outgoing-counter + 1
    return @outgoing-counter

  get-next-incoming-counter: ->
    @incoming-counter = @incoming-counter + 1
    return @incoming-counter

  perform-request: (done, action, response, ...args) ->
    {send-req, outgoing-tasks} = self = @
    counter = self.get-next-outgoing-counter!
    now = new Date!
    index = now - 0
    index = "#{index}#{INDEX_SEPARATOR}#{counter}"
    packet = index: index, action: action, response: response, args: args
    task = packet: packet, start: now, done: done, expire: TASK_EXPIRATION_PERIOD, in-or-out: \outgoing
    return send-req packet unless response
    outgoing-tasks[index] = task
    return send-req packet

  handle-expired-outgoing-task: (index, task) ->
    {done, packet} = task
    {action, args} = packet
    return done "#{action}[#{index}] with args (#{JSON.stringify args}) is expired", null

  handle-expired-incoming-task: (index, task) ->
    return @.response-error index, "expired"

  review-tasks: (tasks, func) ->
    self = @
    expired-tasks = self.decrease-task-timer-counter tasks
    for index, task of expired-tasks
      {start, in-or-out, packet} = task
      {action, args} = packet
      WARN "#{in-or-out}:#{action}[#{index}] with args (#{JSON.stringify args}) is expired"
      func.apply self, [index, task]
      delete tasks[index]

  at-timeout: ->
    {incoming-tasks, outgoing-tasks} = self = @
    self.review-tasks incoming-tasks, self.handle-expired-incoming-task
    self.review-tasks outgoing-tasks, self.handle-expired-outgoing-task

  decrease-task-timer-counter: (tasks)->
    for index, t of tasks
      t.expire = t.expire - 1
    return { [index, t] for index, t of tasks when t.expire <= 0 }



# Request and Response commander.
#
class RaR
  (@name, @opts, @context) ->
    @implementation = new RaR_Impl name, opts, context

  # Clear all resources used in the RaR commander.
  #
  clear: ->
    return @implementation.clear!

  # Set the function for sending outgoing packet via REQUEST channel.
  #
  # RaR shall call this function with one argument `packet` to deliver
  # a pakcet object with request information to remote/peer side. The
  # packet object contains following fields:
  #
  #   - `index`, the unique numeric identity for this request.
  #   - `action`, the name of request
  #   - `response`, indicates the request requires response confirmation from peer or not
  #   - `args`, an array of arguments for the request
  #
  #
  #
  set-outgoing-req: (send-req) ->
    return @implementation.set-outgoing-req send-req

  # Set the function for sending outgoing packet via RESPONSE channel
  #
  set-outgoing-rsp: (send-rsp) ->
    return @implementation.set-outgoing-rsp send-rsp

  # Process the incoming packet from REQUEST channel
  #
  process-incoming-req: (packet) ->
    return @implementation.process-incoming-req packet

  # Process the incoming packet from RESPONSE channel
  #
  process-incoming-rsp: (packet) ->
    return @implementation.process-incoming-rsp packet

  # Perform a request to peer.
  #
  # For example, peer side implements a Time service that convert year/month/date
  # to milliseconds. Then, you can call `perform-request` in this way:
  #
  # ```livescript
  #
  #   perform-request 'time2ms', yes, 2017, 11, 03, (err, milliseconds) ->
  #     return console.log "failed to time2ms, err: #{err}" if err?
  #     return console.log "2017/11/03 => #{milliseconds}"
  #
  # ```
  #
  # The peer side shall have a Time object as `context`, that has a function `time2ms`
  # implemented in this way:
  #
  # ```livescript
  #
  #   class Time
  #     (@opts) -> return
  #
  #     time2ms: (done, year, month, day) ->
  #       return done "less than 1970" if year < 1970
  #       f = -> return done null, (new Date year, month, day) - 0
  #       return setTimeout f, 500ms
  #
  # ```
  #
  perform-request: (done, action, response, ...args) ->
    return @implementation.perform-request.apply @implementation, arguments



const REQUEST_CHANNEL = \request
const RESPONSE_CHANNEL = \response

create-rr-commander = (name, opts, context) -> return new RaR name, opts, context

module.exports = exports = {create-rr-commander, REQUEST_CHANNEL, RESPONSE_CHANNEL}