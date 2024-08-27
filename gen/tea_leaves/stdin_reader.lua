local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local assert = _tl_compat and _tl_compat.assert or assert; local string = _tl_compat and _tl_compat.string or string; local _module_name = "stdin_reader"


local lusc = require("lusc")
local asserts = require("tea_leaves.asserts")
local uv = require("luv")
local tracing = require("tea_leaves.tracing")
local class = require("tea_leaves.class")

local StdinReader = {}








function StdinReader:__init()
   self._buffer = ""
   self._disposed = false
   self._chunk_added_event = lusc.new_pulse_event()
end

function StdinReader:initialize()
   self._stdin = uv.new_pipe(false)
   asserts.that(self._stdin ~= nil)
   assert(self._stdin:open(0))
   tracing.trace(_module_name, "Opened pipe for stdin.  Now waiting to receive data...")

   assert(self._stdin:read_start(function(err, chunk)
      if self._disposed then
         return
      end
      assert(not err, err)
      if chunk then
         tracing.trace(_module_name, "Received new data chunk from stdin: {}", { chunk })

         self._buffer = self._buffer .. chunk
         self._chunk_added_event:set()
      end
   end))
end

function StdinReader:dispose()
   asserts.that(not self._disposed)
   self._disposed = true
   assert(self._stdin:read_stop())
   self._stdin:close()
   tracing.debug(_module_name, "Closed pipe for stdin")
end

function StdinReader:read_line()
   asserts.that(not self._disposed)
   tracing.trace(_module_name, "Attempting to read line from stdin...")
   asserts.that(lusc.is_available())

   while true do
      local i = self._buffer:find("\n")

      if i then
         local line = self._buffer:sub(1, i - 1)
         self._buffer = self._buffer:sub(i + 1)
         line = line:gsub("\r$", "")
         tracing.trace(_module_name, "Successfully parsed line from buffer: {line}.  Buffer is now: {buffer}", { line, self._buffer })
         return line
      else
         tracing.trace(_module_name, "No line available yet.  Waiting for more data...", {})
         self._chunk_added_event:await()
         tracing.trace(_module_name, "Checking stdin again for new line...", {})
      end
   end
end

function StdinReader:read(len)
   asserts.that(not self._disposed)
   tracing.trace(_module_name, "Attempting to read {len} characters from stdin...", { len })

   asserts.that(lusc.is_available())

   while true do
      if #self._buffer >= len then
         local data = self._buffer:sub(1, len)
         self._buffer = self._buffer:sub(#data + 1)
         return data
      end

      self._chunk_added_event:await()
   end
end

class.setup(StdinReader, "StdinReader", {
   nilable_members = { '_stdin' },
})

return StdinReader
