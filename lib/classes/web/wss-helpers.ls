{DBG, ERR, WARN, INFO} = global.get-logger __filename


const INDEX_SEPARATOR = "_"
const TASK_EXPIRATION_PERIOD = 30s

const REQUEST_CHANNEL = \request
const RESPONSE_CHANNEL = \response


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
    return WARN "[#{name}] process-request-packet(): missing index" unless index?
    return self.response-error index, "missing action" unless action?
    return self.response-error index, "invalid args for #{action}" unless Array.isArray args
    now = new Date!
    func-name = "process_request_#{action}"
    func = context[func-name]
    return self.response-error index, "missing handler for action[#{action}]: #{func-name}()" unless func?
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
    return WARN "[#{name}] process-response-packet(): missing index" unless index?
    t = outgoing-tasks[index]
    return WARN "[#{name}] tasks[#{index}] => too late since task is deleted" unless t?
    delete outgoing-tasks[index]
    {done} = t
    return done error, result

  response-error: (index, error) ->
    {send-rsp} = self = @
    packet = index: index, result: null, error: error
    return send-rsp RESPONSE_CHANNEL, packet

  response-okay: (index, result) ->
    {send-rsp} = self = @
    packet = index: index, result: result, error: null
    return send-rsp RESPONSE_CHANNEL, packet

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

  perform-request: (action, response, ...done) ->
    {send-req, outgoing-tasks} = self = @
    counter = self.get-next-outgoing-counter!
    args = Array.from arguments
    args.shift!
    args.shift!
    args.pop!
    now = new Date!
    index = now - 0
    index = "#{index}#{INDEX_SEPARATOR}#{counter}"
    packet = index: index, action: action, response: response, args: args
    task = packet: packet, start: now, done: done, expire: TASK_EXPIRATION_PERIOD, in-or-out: \outgoing
    return send-req packet unless response
    outgoing-tasks[index] = task
    return send-req REQUEST_CHANNEL, packet

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
      {expire} = t
      t.expire = expire - 1
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

  # Set the function for sending outgoing packet via REQUEST channel
  #
  set-outgoing-req: (send-req) ->
    return @implementation.set-outgoing-req ...

  # Set the function for sending outgoing packet via RESPONSE channel
  #
  set-outgoing-rsp: (send-rsp) ->
    return @implementation.set-outgoing-rsp ...

  # Process the incoming packet from REQUEST channel
  #
  process-incoming-req: (packet) ->
    return @implementation.process-incoming-req ...

  # Process the incoming packet from RESPONSE channel
  #
  process-incoming-rsp: (packet) ->
    return @implementation.process-incoming-rsp ...



module.exports = exports =
  create-rr-commander: (name, opts, context) -> return new RaR name, opts, context
  REQUEST_CHANNEL: REQUEST_CHANNEL
  RESPONSE_CHANNEL: RESPONSE_CHANNEL

