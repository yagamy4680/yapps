##
# Inspired by these documents and codes:
#   - https://github.com/tapjs/signal-exit/blob/master/signals.js
#   - ...
#
#
# https://nodejs.org/api/process.html#process_exit_codes
# Exit Code:
#   https://nodejs.org/api/process.html#process_signal_events
#   - `1` Uncaught Fatal Exception
#   - `2` Unused (reserved by Bash for builtin misuse)
#   - `3` Internal JavaScript Parse Error
#   - `4` Internal JavaScript Evaluation Failure
#   - `5` Fatal Error
#   - `6` Non-function Internal Exception Handler
#   - `7` Internal Exception Handler Run-Time Failure
#   - `8` Unused
#   - `9` Invalid Argument
#   - `10` Internal JavaScript Run-Time Failure
#   - `11` Unused
#   - `12` Invalid Debug Argument
#   - `>128` Signal Exits -
#       If Node.js receives a fatal signal such as SIGKILL or SIGHUP, then
#       its exit code will be 128 plus the value of the signal code.
#       This is a standard POSIX practice, since exit codes are defined to
#       be 7-bit integers, and signal exits set the high-order bit, and then
#       contain the value of the signal code. For example, signal SIGABRT has
#       value 6, so the expected exit code will be 128 + 6, or 134.
#
#
# http://man7.org/linux/man-pages/man7/signal.7.html
#   SIGHUP        1       Term    Hangup detected on controlling terminal or death of controlling process
#   SIGINT        2       Term    Interrupt from keyboard
#   SIGQUIT       3       Core    Quit from keyboard
#   SIGILL        4       Core    Illegal Instruction
#   SIGABRT       6       Core    Abort signal from abort(3)
#   SIGFPE        8       Core    Floating-point exception
#   SIGKILL       9       Term    Kill signal
#   SIGSEGV      11       Core    Invalid memory reference
#   SIGPIPE      13       Term    Broken pipe: write to pipe with no readers
#   SIGALRM      14       Term    Timer signal from alarm(2)
#   SIGTERM      15       Term    Termination signal
#   SIGUSR1   30,10,16    Term    User-defined signal 1
#   SIGUSR2   31,12,17    Term    User-defined signal 2
#   SIGCHLD   20,17,18    Ign     Child stopped or terminated
#   SIGCONT   19,18,25    Cont    Continue if stopped
#   SIGSTOP   17,19,23    Stop    Stop process
#   SIGTSTP   18,20,24    Stop    Stop typed at terminal
#   SIGTTIN   21,21,26    Stop    Terminal input for background process
#   SIGTTOU   22,22,27    Stop    Terminal output for background process
#
#
# http://tldp.org/LDP/abs/html/exitcodes.html
# Exit Codes With Special Meanings (Advanced Bash-Scripting Guide)
#   1    Catchall for general errors
#   2    Misuse of shell builtins (according to Bash documentation)
#   126  Command invoked cannot execute
#   127  Command not found
#   128  Invalid argument to exit
#   130  Script terminated by Control-C
#   255  Exit status out of range
#
#
# https://nodejs.org/api/process.html#process_signal_events
#   SIGUSR1   , reserved by Node.js to start the debugger
#   SIGTERM
#   SIGINT    , reset the terminal mode before exiting with code 128 + signal number. If one of these signals has a listener installed, its default behavior will be removed
#   SIGKILL   , unconditionally terminate Node.js on all platforms
#   SIGHUP    , generated on Windows when the console window is closed
#
#
# $ kill -l
#
#  1) SIGHUP       2) SIGINT       3) SIGQUIT      4) SIGILL       5) SIGTRAP
#  6) SIGABRT      7) SIGBUS       8) SIGFPE       9) SIGKILL     10) SIGUSR1
# 11) SIGSEGV     12) SIGUSR2     13) SIGPIPE     14) SIGALRM     15) SIGTERM
# 16) SIGSTKFLT   17) SIGCHLD     18) SIGCONT     19) SIGSTOP     20) SIGTSTP
# 21) SIGTTIN     22) SIGTTOU     23) SIGURG      24) SIGXCPU     25) SIGXFSZ
# 26) SIGVTALRM   27) SIGPROF     28) SIGWINCH    29) SIGIO       30) SIGPWR
# 31) SIGSYS      34) SIGRTMIN    35) SIGRTMIN+1  36) SIGRTMIN+2  37) SIGRTMIN+3
# 38) SIGRTMIN+4  39) SIGRTMIN+5  40) SIGRTMIN+6  41) SIGRTMIN+7  42) SIGRTMIN+8
# 43) SIGRTMIN+9  44) SIGRTMIN+10 45) SIGRTMIN+11 46) SIGRTMIN+12 47) SIGRTMIN+13
# 48) SIGRTMIN+14 49) SIGRTMIN+15 50) SIGRTMAX-14 51) SIGRTMAX-13 52) SIGRTMAX-12
# 53) SIGRTMAX-11 54) SIGRTMAX-10 55) SIGRTMAX-9  56) SIGRTMAX-8  57) SIGRTMAX-7
# 58) SIGRTMAX-6  59) SIGRTMAX-5  60) SIGRTMAX-4  61) SIGRTMAX-3  62) SIGRTMAX-2
# 63) SIGRTMAX-1  64) SIGRTMAX
#
#
# /usr/include/sysexits.h
# #define EX_OK           0   /* successful termination */
# #define EX__BASE        64  /* base value for error messages */
# #define EX_USAGE        64  /* command line usage error */
# #define EX_DATAERR      65  /* data format error */
# #define EX_NOINPUT      66  /* cannot open input */
# #define EX_NOUSER       67  /* addressee unknown */
# #define EX_NOHOST       68  /* host name unknown */
# #define EX_UNAVAILABLE  69  /* service unavailable */
# #define EX_SOFTWARE     70  /* internal software error */
# #define EX_OSERR        71  /* system error (e.g., can't fork) */
# #define EX_OSFILE       72  /* critical OS file missing */
# #define EX_CANTCREAT    73  /* can't create (user) output file */
# #define EX_IOERR        74  /* input/output error */
# #define EX_TEMPFAIL     75  /* temp failure; user is invited to retry */
# #define EX_PROTOCOL     76  /* remote error in protocol */
# #define EX_NOPERM       77  /* permission denied */
# #define EX_CONFIG       78  /* configuration error */
#
#
# [Windows Exit Codes]
# https://www.symantec.com/connect/articles/windows-system-error-codes-exit-codes-description
#
# 137, `kill -KILL [PID]` => SIGKILL
# 143, `kill [PID]`       => SIGTERM
# 140, `kill -USR2 [PID]` => SIGUSR2
#
# => Restart (needs parent monitor to run the daemon/app again)
#     send "restart" command to app's unixsock (if finalization is done well within N seconds, then exit 96)
#     if exit-code is 96, then continue infinite-startup-loop
#
# => Shutdown (needs to let parent monitor to know we'd like to shutdown):
#     send "shutdown" command to app's unixsock (if finalization is done well within N seconds, then exit 0)
#
#     if exit-code is 0, then break infinite-startup-loop
#     if wait more than N seconds, then send SIGKILL
#     if exit-code is 137, then break infinite-startup-loop
#
# => Reload (similar to restart, but shall be triggered by a command sent via unixsock)
#     send SIGUSR2
#     if exit-code is 140, then continue infinite-startup-loop
#
# kill -USR1 `cat /var/run/nginx.pid`
#

const SIGNALS =
  SIGHUP: 1
  SIGINT: 2
  SIGABRT: 6
  SIGALRM: 14
  SIGTERM: 15
  SIGUSR2: 12

const SUICIDE_TIMEOUT = 10s    # How long to wait before giving up on graceful shutdown
{DBG, INFO, WARN, ERR} = global.get-logger __filename


class SuicideTimer
  (@evt, @seconds) ->
    self = @
    f = -> return self.at-check!
    self.interval = setInterval f, 1000ms

  at-check: ->
    {evt, seconds, interval} = self = @
    self.seconds = seconds - 1
    text = "#{self.seconds}"
    return INFO "#{evt.red}: peaceful shutdown remains #{text.cyan} seconds ..." if self.seconds > 0
    ERR "#{evt.red}: peaceful shutdown but timeout, exit: 125"
    clearInterval interval
    return process.exit 125


SIGNAL_HANDLER_CURRYING = (evt, dummy) -->
  {app, suicide_timeout} = module
  WARN "receive #{evt.red} event"
  prefix = "signal[#{evt.red}]"
  return WARN "#{prefix}: already shutdowning ..." if app.shutdowning
  module.timer = new SuicideTimer evt, suicide_timeout
  WARN "#{prefix}: yapps doesn't support config-reloading now, let's restart directly" if evt is \SIGUSR2
  INFO "#{prefix}: start peaceful shutdown ..."
  code = SIGNALS[evt]
  try
    (err) <- app.shutdown evt
    ERR err, "peaceful shutdown for signal #{evt.red} event but known error" if err?
    return process.exit (code + 128)
  catch error
    ERR error, "peaceful shutdown for signal #{evt.red} event but uncaught error, exit: #{code} + 192"
    return process.exit (code + 192)


UNCAUGHT_EXCEPTION_HANDLER = (err, origin) ->
  {app, suicide_timeout} = module
  console.dir err
  evt = "uncaught-exception(#{origin}): #{err.message}"
  prefix = "uncaught-exception"
  WARN "receive #{evt.red} event"
  return WARN "#{prefix}: already shutdowning ..." if app.shutdowning
  module.timer = new SuicideTimer evt, suicide_timeout
  INFO "#{prefix}: start peaceful shutdown ..."
  try
    (err) <- app.shutdown evt
    ERR err, "#{prefix}: peaceful shutdown for signal #{evt.red} event but known error" if err?
    return process.exit 127
  catch error
    ERR error, "#{prefix}: peaceful shutdown for signal #{evt.red} event but uncaught error"
    return process.exit 192


module.exports = exports = (app) ->
  module.app = app
  module.suicide_timeout = SUICIDE_TIMEOUT
  signals = [ k for k, v of SIGNALS ]
  for s in signals
    listener = SIGNAL_HANDLER_CURRYING s
    process.on s, listener
    DBG "register signal event: #{s.red}"
  process.on 'uncaughtException', UNCAUGHT_EXCEPTION_HANDLER
  DBG "register uncaught-exception"
  return app
