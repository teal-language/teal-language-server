
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

function util.binary_search<T, U>(list: {T}, item: U, cmp: function(T, U): boolean): integer, T
   local len <const> = #list
   local mid: integer
   local s, e = 1, len
   while s <= e do
      mid = math.floor((s + e) / 2)
      local val <const> = list[mid]
      local res <const> = cmp(val, item)
      if res then
         if mid == len then
            return mid, val
         else
            if not cmp(list[mid + 1], item) then
               return mid, val
            end
         end
         s = mid + 1
      else
         e = mid - 1
      end
   end
end

return util
