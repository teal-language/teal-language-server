local util <const> = require("tealls.util")

local enum IoMode
   "blocking"
   "evented"
end

local loop <const> = {
   io_mode: IoMode = "blocking",
}

local work: {thread} = {}

function loop.enqueue(fn: function)
   print("enqueuing work")
   table.insert(work, coroutine.create(fn))
end

local cancel <const> = {}

-- drop the current coroutine from the work queue
function loop.cancel()
   coroutine.yield(cancel)
end

local main_thread <const> = coroutine.create(function()
   while true do
      local current_work = work
      work = {}
      if #current_work == 1 then
         loop.io_mode = "blocking"
      end
      for _, job in ipairs(current_work) do
         local ok, val = coroutine.resume(job)
         assert(ok, val)
         if val == cancel then
            util.log(("Job %s was cancelled"):format(tostring(job)))
         end
         if coroutine.status(job) ~= "dead"
            and val ~= cancel then
            table.insert(work, job)
         end
         loop.io_mode = "evented"
         coroutine.yield()
      end
   end
end)

function loop.step(): boolean
   local ok, err = coroutine.resume(main_thread)
   util.assert(ok, tostring(err))
   return coroutine.status(main_thread) ~= "dead"
end

return loop
