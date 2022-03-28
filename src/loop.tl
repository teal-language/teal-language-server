local poll <const> = require("tealls.poll")
local util <const> = require("tealls.util")

local enum IoMode
   "blocking"
   "evented"
end

local loop <const> = {
   IoMode = IoMode,
   io_mode: IoMode = "blocking",
}

local work: {thread} = {}

function loop.enqueue(fn: function)
   table.insert(work, coroutine.create(fn))
end

local cancel <const> = {}

-- drop the current coroutine from the work queue
function loop.cancel()
   coroutine.yield(cancel)
end

local main_thread <const> = coroutine.create(function()
   while true do
      local current_work <const> = work
      work = {}
      if #current_work == 1 then
         loop.io_mode = "blocking"
      end
      for _, job in ipairs(current_work) do
         local ok, val = coroutine.resume(job)
         assert(ok, val)
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

function loop.read(patt: string | integer, force: boolean): string
   if loop.io_mode == "evented" and not force then
      util.log("Waiting for stdin data...")
      repeat
         local has_data <const>, err <const> = poll()
         assert(not err, err)
         if not has_data then
            coroutine.yield()
         end
      until has_data
   end
   local result = assert(io.stdin:read(patt))
   -- util.log("Completed stdin read: '" .. result .. "'")
   return result
end

function loop.yield()
   coroutine.yield()
end

return loop
