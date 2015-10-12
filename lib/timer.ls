require! <[moment]>
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

timerCbCurrying = (timer, dummy) --> return timer.check!


module.exports = exports = class Timer
  (@period, x, y, z) ->
    DBG "initiate timer w/ period = #{period}"
    @args = []
    @obj = null
    @interval_obj = null
    @last_invocation = null
    @callback = timerCbCurrying @

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
    @interval_obj = setInterval @callback, 500ms
    @last_invocation = moment!


  start: ->
    @running = yes


  stop: ->
    @running = no


  cleanup: ->
    @running = no
    clearInterval @interval_obj


  configure: (@period) -> return


  getPeriod: -> return @period


  check: ->
    return unless @running
    now = moment!
    now.subtract @period, \seconds
    if now > @last_invocation
      @func.apply @obj, @args
      @last_invocation = moment!
