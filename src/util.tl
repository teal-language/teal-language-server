
local json <const> = require("dkjson")
local util <const> = {}

function util.keys<K, V>(t: {K:V}): {K}
   local ks: {K} = {}
   for k in pairs(t) do
      table.insert(ks, k)
   end
   return ks
end

function util.map<K, V, T>(t: {K:V}, fn: function(V): T): {K:T}
   local new: {K:T} = {}
   for k, v in pairs(t) do
      new[k] = fn(v)
   end
   return new
end

function util.imap<V, T>(t: {V}, fn: function(V): (T), start: integer, finish: integer): {T}
   local new: {T} = {}
   for i = start or 1, finish or #t do
      new[i] = fn(t[i])
   end
   return new
end

local req <const> = require
local _inspect: function(any): string
do
   local ok, actual_inspect = pcall(req, "inspect") as (boolean, function(any): string)
   if ok then
      _inspect = actual_inspect
   else
      _inspect = tostring
   end
end

local function inspect(x: any): string
   -- TODO upstream: using 'is' gives a warning about not being able to narrow this, which seems wrong?
   return type(x) == "string"
      and x as string
      or _inspect(x)
end

local logging_enabled = true
function util.set_logging(to: boolean)
   logging_enabled = to
end

local logfile <const> = "/tmp/teal-language-server.log"
function util.log(...: any)
   if logging_enabled then
      local fh <const> = assert(io.open(logfile, "w"))
      fh:write("[", os.date("%X"), "] ")
      for i = 1, select("#", ...) do
         local x <const> = select(i, ...)
         fh:write(inspect(x))
      end
      fh:write("\n")
      fh:close()
   end
end

function util.assert<T>(val: T, msg: string): T
   if not val then
      util.log("ASSERTION FAILED: ", msg)
      error(msg, 2)
   end
   return val
end

function util.json_nullable<T>(x: T): T
   if x == nil then
      return json.null as T
   end
   return x
end

-- Binary search a list
-- Predicate return vals
--      < 0: result is before current guess
--      > 0: result is after current guess
--      = 0: result is current guess, stop searching
-- Returns the index of the found object and the found object
function util.binary_search<T>(list: {T}, predicate: function(T): integer): integer, T
   if #list < 2 then
      return 1
   end
   local max_steps = math.ceil(math.log(#list, 2)) + 2
   local guess = #list // 2
   local factor = #list // 4
   for _ = 1, max_steps do
      local res <const> = predicate(list[guess])
      if res > 0 then
         guess = guess + factor
      elseif res < 0 then
         guess = guess - factor
      else
         return guess, list[guess]
      end
      guess = math.min(math.max(guess, 1), #list)
      factor = math.max(factor // 2, 1)
   end
   return guess, list[guess]
end

return util
