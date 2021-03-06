"""
A `Process` is an abstraction for an event yielding function, i.e. a process function.

The process function can suspend its execution by yielding an instance of `AbstractEvent`. The `Environment` will take care of resuming the process function with the value of that event once it has happened. The exception of failed events is also thrown into the process function.

A `Process` is a subtype of `AbstractEvent`. It is triggered, once the process functions returns or raises an exception. The value of the process is the return value of the process function or the exception, respectively.

**Signature**:

Process{E<:Environment} <: AbstractEvent{E}

**Fields**:

- bev :: BaseEvent{E}
- task :: Task
- target :: AbstractEvent{E}
- resume :: Function

**Constructor**:

Process{E<:Environment}(func::Function, env::E, args::Any...)
"""
type Process{E<:Environment} <: AbstractProcess{E}
  bev :: BaseEvent{E}
  task :: Task
  target :: AbstractEvent{E}
  resume :: Function
  function Process{E}(func::Function, env::E, args::Any...) where E<:Environment
    proc = new()
    proc.bev = BaseEvent(env)
    proc.task = @task func(env, args...)
    proc.target = Timeout(env)
    proc.resume = append_callback(execute, proc.target, proc)
    return proc
  end
end

function Process{E<:Environment}(func::Function, env::E, args::Any...)
  Process{E}(func, env, args...)
end

"""
Creates a `Process` with process function `func` having a required argument `env`, i.e. an instance of a subtype of `Environment`, and a variable number of arguments `args...`.

**Signature**:

@Process func(env, args...)
"""
macro Process(ex)
  if ex.head == :call
    func = esc(ex.args[1])
    args = [esc(ex.args[n]) for n in 2:length(ex.args)]
    return :(Process($(func), $(args...)))
  end
end

function yield{E<:Environment}(target::AbstractEvent{E})
  env = environment(target)
  proc = active_process(env)
  proc.target = state(target) == triggered ? Timeout(env, value=value(target)) : target
  proc.resume = append_callback(execute, proc.target, proc)
  ret = SimJulia.produce(nothing)
  isa(ret, Exception) && throw(ret)
  return ret
end

function execute{E<:Environment}(ev::AbstractEvent{E}, proc::Process{E})
  try
    env = environment(ev)
    set_active_process(env, proc)
    ret = SimJulia.consume(proc.task, value(ev))
    set_active_process(env)
    istaskdone(proc.task) && schedule(proc.bev, value=ret)
  catch exc
    rethrow(exc)
  end
end

function interrupt(proc::Process, cause::Any=nothing)
  if !istaskdone(proc.task)
    remove_callback(proc.resume, proc.target)
    proc.target = Timeout(environment(proc), priority=typemax(Int8), value=InterruptException(proc, cause))
    proc.resume = append_callback(execute, proc.target, proc)
  end
end
