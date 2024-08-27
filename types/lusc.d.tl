
local record lusc
   record Scheduler
      schedule:function(Scheduler, delay_seconds:number, callback:function())
      dispose:function(Scheduler)
   end

   record DefaultScheduler
      schedule:function(DefaultScheduler, delay_seconds:number, callback:function())
      dispose:function(DefaultScheduler)

      new:function():DefaultScheduler
   end

   record Channel<T>
      --- Only needed when there is a buffer max size
      -- @return true if the receiving side is closed, in which
      -- case there is no need to send any more values
      await_send:function(Channel<T>, value:T)

      --- raises an error if the buffer is full
      -- @return true if the receiving side is closed, in which
      -- case there is no need to send any more values
      send:function(Channel<T>, value:T)

      --- @return true if both the sending side is closed and there are no more
      -- @return received value
      -- values to receive
      await_receive_next:function(Channel<T>):T, boolean

      as_iterator:function(Channel<T>):(function():T)

      --- Receives all values, until sender is closed
      await_receive_all:function(Channel<T>):function():T

      --- raises an error if nothing is there to receive
      -- @return received value
      -- @return true if both the sending side is closed and there are no more
      -- values to receive
      receive_next:function(Channel<T>):T, boolean

      --- Indicates that the sender has completed and receiver can end
      close:function(Channel<T>)

      -- Just calls close() after the given function completes
      close_after:function(Channel<T>, function())

      is_closed: function(Channel<T>):boolean
   end

   record Opts
      -- Default: false
      generate_debug_names:boolean

      -- err is nil when completed successfully
      on_completed: function(err:ErrorGroup)

      -- Optional - by default it uses luv timer
      scheduler_factory: function():Scheduler
   end

   record ErrorGroup
      errors:{any}
      new:function({any}):ErrorGroup
   end

   record Task
      record Opts
         name:string
      end

      parent: Task
      total_active_time: number
   end

   record StickyEvent
      is_set:boolean

      unset:function(StickyEvent)
      set:function(StickyEvent)
      await:function(StickyEvent)
   end

   record PulseEvent
      set:function(PulseEvent)
      await:function(PulseEvent)
   end

   record CancelledError
   end

   record DeadlineOpts
      -- note: can only set one of these
      move_on_after:number
      move_on_at:number
      fail_after:number
      fail_at:number
   end

   record CancelScope
      record Opts
         shielded: boolean
         name:string

         -- note: can only set one of these
         move_on_after:number
         move_on_at:number
         fail_after:number
         fail_at:number
      end

      record ShortcutOpts
         shielded: boolean
         name:string
      end

      record Result
         was_cancelled: boolean
         hit_deadline: boolean
      end

      has_cancelled:function(CancelScope):boolean

      cancel:function(CancelScope)
   end

   record Nursery
      record Opts
         name:string

         shielded: boolean

         -- note: can only set one of these
         move_on_after:number
         move_on_at:number
         fail_after:number
         fail_at:number
      end

      cancel_scope: CancelScope

      -- TODO
      -- start:function()

      start_soon:function(self: Nursery, func:function(), Task.Opts)
   end

   open_nursery:function(handler:function(nursery:Nursery), opts:Nursery.Opts):CancelScope.Result
   get_time:function():number
   await_sleep:function(seconds:number)
   await_until:function(until_time:number)
   await_forever:function()
   new_sticky_event:function():StickyEvent
   new_pulse_event:function():PulseEvent
   start:function(opts:Opts)

   -- Note that this will only cancel tasks if one of the move_on* or fail_* options
   -- are provided.  Otherwise it will wait forever for tasks to complete gracefully
   -- Note also that if block_until_stopped is provided, it will block
   stop:function(opts:DeadlineOpts)

   -- Long running tasks can check this periodically, and then shut down
   -- gracefully, instead of relying on cancels
   -- Can also observe via the subscribe_ methods below
   stop_requested:function():boolean

   subscribe_stop_requested:function(observer:function())
   unsubscribe_stop_requested:function(observer:function())

   -- If true, then the current code is being executed
   -- under the lusc task loop and therefore lusc await
   -- methods can be used
   is_available:function():boolean

   try_get_async_local:function(key:any):any
   set_async_local:function(key:any, value:any)

   move_on_after:function(delay_seconds:number, handler:function(scope:CancelScope), opts:CancelScope.ShortcutOpts):CancelScope.Result
   move_on_at:function(delay_seconds:number, handler:function(scope:CancelScope), opts:CancelScope.ShortcutOpts):CancelScope.Result
   fail_after:function(delay_seconds:number, handler:function(scope:CancelScope), opts:CancelScope.ShortcutOpts):CancelScope.Result
   fail_at:function(delay_seconds:number, handler:function(scope:CancelScope), opts:CancelScope.ShortcutOpts):CancelScope.Result

   cancel_scope:function(handler:function(scope:CancelScope), opts:CancelScope.Opts):CancelScope.Result

   --- @return true if the given object is an instance of ErrorGroup
   -- and also that it only consists of the cancelled error
   is_cancelled_error:function(err:any):boolean

   schedule:function(handler:function(), opts:Task.Opts)

   schedule_wrap: function(function(), opts:Task.Opts): function()
   schedule_wrap: function<T>(function(T), opts:Task.Opts): function(T)
   schedule_wrap: function<T1,T2>(function(T1, T2), opts:Task.Opts): function(T1, T2)

   has_started:function():boolean

   get_root_nursery:function():Nursery

   cancel_all:function()
   open_channel:function<T>(max_buffer_size:integer):Channel<T>

   get_running_task:function():Task
   try_get_running_task:function():Task

   force_unavailable:function<T>(handler:function():T):T
   force_unavailable_wrap:function(handler:function()):function()

   set_log_handler:function(function(message:string))

   set_impl:function(any)
end

return lusc

