#!/usr/bin/env lsc
#
require! <[moment colors]>
require \../../yap-simple-logger/lib/yap-simple-logger.ls .init __filename, __filename, moment, colors

global.get-bundled-modules = ->
  lodash_merge = require \lodash/merge
  lodash_sortBy = require \lodash/sortBy
  lodash_findIndex = require \lodash/findIndex
  lodash_padEnd = require \lodash/padEnd
  lodash_padStart = require \lodash/padStart
  async = require \async
  return {async, lodash_merge, lodash_sortBy, lodash_findIndex, lodash_padStart, lodash_padEnd}

SystemUptime = require \../lib/helpers/system-uptime
DataJobQueue = require \../lib/helpers/data-job-queue
backend = require \./common-fs-backend

{DBG, ERR, WARN, INFO} = global.get-logger __filename

SERIALIZER = (data, done) ->
  try
    text = JSON.stringify data
  catch error
    return done error
  return done null, new Buffer text

DESERIALIZER = (buffer, done) ->
  try
    text = buffer.toString!
    json = JSON.parse text
  catch error
    return done error
  return done null, json

CONSUMER = (name, format, timestamp, data, done) ->
  {boots, uptime, epoch} = timestamp
  len = if Buffer.isBuffer data or \string is typeof data then data.length else (JSON.stringify data).length
  INFO "consuming #{boots}-#{uptime}-#{epoch}.#{format}, with #{len} bytes."
  return done "remote server is not ready" unless module.okay
  f = -> return done!
  setTimeout f, 3000ms
  # return done!


PRODUCER = ->
  cpu = process.cpuUsage!
  mem = process.memoryUsage!
  env = process.env
  data = {cpu, mem, env}
  INFO "inserting #{JSON.stringify cpu}, #{JSON.stringify mem}"
  return q.enqueue data

OKAY = ->
  module.okay = yes


module.okay = no
uptime = new SystemUptime {}
q_opts =
  verbose: yes
  job:
    data_format: \json
    serializer: SERIALIZER
    deserializer: DESERIALIZER
  intervals:
    check: 500ms
    consume: 1500ms
    store: 3000ms
  consumer: CONSUMER
  backend: backend

q = global.q = new DataJobQueue \abc, uptime, q_opts
(uptime-init-err) <- uptime.init
return ERR "failed to initialize system-uptime, err: #{uptime-init-err}" if uptime-init-err?
(init-err) <- q.init
ERR "failed to initialize queue, err: #{init-err}" if init-err?
setInterval PRODUCER, 1000ms
setTimeout OKAY, 8s * 1000ms