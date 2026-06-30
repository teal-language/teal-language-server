local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local debug = _tl_compat and _tl_compat.debug or debug; local io = _tl_compat and _tl_compat.io or io; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local os = _tl_compat and _tl_compat.os or os; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _tl_table_unpack = unpack or table.unpack; local luv = require("luv")
local cjson = require("cjson")


local _unpack = unpack or _tl_table_unpack



local logging = {}



























local LoggerBase = {}
function LoggerBase:set_level(log_level)
   self.current_level = logging.log_levels[log_level]
end

function LoggerBase:trace(message, ...)
   logging._logger_handler("TRACE", message, self.name, self.current_level, ...)
end

function LoggerBase:debug(message, ...)
   logging._logger_handler("DEBUG", message, self.name, self.current_level, ...)
end

function LoggerBase:info(message, ...)
   logging._logger_handler("INFO", message, self.name, self.current_level, ...)
end

function LoggerBase:warning(message, ...)
   logging._logger_handler("WARNING", message, self.name, self.current_level, ...)
end

function LoggerBase:error(message, ...)
   logging._logger_handler("ERROR", message, self.name, self.current_level, ...)
end

function LoggerBase:critical(message, ...)
   logging._logger_handler("CRITICAL", message, self.name, self.current_level, ...)
end

local function eprint(error_message)
   io.stderr:write(error_message)
   io.stderr:write("\n")
end

logging.loggers = {}
logging.logger_func = eprint
logging.current_level = 30
logging.log_levels = {
   ["TRACE"] = 0,
   ["DEBUG"] = 10,
   ["INFO"] = 20,
   ["WARNING"] = 30,
   ["ERROR"] = 40,
   ["CRITICAL"] = 50,
}

function logging.get_logger(name)
   name = name or debug.getinfo(2, "S").short_src
   if logging.loggers[name] then
      return logging.loggers[name]
   end

   logging.loggers[name] = setmetatable({}, { __index = LoggerBase })
   logging.loggers[name].name = name

   return logging.loggers[name]
end

function logging.set_level(log_level)
   logging.current_level = logging.log_levels[log_level]
end

function logging._logger_handler(message_level, message, logger_name, logger_log_level, ...)
   local args = { ... }
   for i, v in ipairs(args) do if type(v) == "table" then args[i] = cjson.encode(v) end end
   if logging.log_levels[message_level] >= (logger_log_level or logging.current_level) then
      if #args > 0 then
         logging.handler(message_level, logger_name, string.format(message, _unpack(args)))
      else
         logging.handler(message_level, logger_name, message)
      end
   end
end

function logging.handler(log_level, logger_name, message)
   local sec, usec = luv.gettimeofday()
   local current_time = os.date("%Y-%m-%d %H:%M:%S", sec) .. "." .. tostring(usec)
   logging.logger_func(string.format("%s %s [%s] %s", current_time, log_level, logger_name, message))
end

return logging
