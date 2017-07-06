{DBG} = global.get-logger __filename

/**
 * Simple Usage for Timer class

    t = new Timer 10s, obj, func
    t = new Timer 10s, obj, func, args
    t = new Timer 10s, func
    t = new Timer 10s, func, args

    t.start!
    t.configure 5s

    t.stop!
    t.cleanup!
 *
 */

module.exports = exports = class Timer
  (@period, x, y, z) ->
    DBG "initiate timer w/ period = #{period}"
    self = @
    @args = []
    @obj = null
    @interval_obj = null
    type = typeof x
    if "function" == type
      @type = "contextless"
      @func = x
      @args = y if y? and "array" == typeof y
    else if "object" == typeof x and "string" == typeof y
      @type = "context"
      @obj = x
      @func = x[y]
      @args = z if z? and "array" == typeof z
      throw new Error "function #{y} not found" unless @func?
    else
      throw new Error "invalid arguments for timer creation"
    @running = no
    @counter = 0
    @callback = -> return self.check!
    @interval_obj = setInterval @callback, 1000ms


  start: ->
    @running = yes
    @counter = @period


  stop: ->
    @counter = 0
    @running = no


  cleanup: ->
    @counter = 0
    @running = no
    clearInterval @interval_obj


  configure: (@period) ->
    @counter = period
    return


  getPeriod: -> return @period


  check: ->
    {running, counter, period} = self = @
    return unless running
    self.counter = self.counter - 1
    return unless self.counter <= 0
    self.counter = period
    {func, obj, args} = self
    return func.apply obj, args

