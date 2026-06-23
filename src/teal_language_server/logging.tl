local luv <const> = require("luv")
local cjson <const> = require("cjson")

global unpack: function
local _unpack = unpack or table.unpack

-- very quick 'n dirty logger. Based off of tested's which is based off of python's, all with a lot less features :P

local record logging
   enum level
      "TRACE" "DEBUG" "INFO" "WARNING" "ERROR" "CRITICAL"
   end

   logger_func: function(string)

   interface Logger
      current_level: integer
      name: string
      set_level: function(self: Logger, log_level: level)
      trace: function(self: Logger, message: string, ...: any)
      debug: function(self: Logger, message: string, ...: any)
      info: function(self: Logger, message: string, ...: any)
      warning: function(self: Logger, message: string, ...: any)
      error: function(self: Logger, message: string, ...: any)
      critical: function(self: Logger, message: string, ...: any)
   end

   loggers: {string: Logger}

   current_level: integer
   log_levels: {level: integer}

   _logger_handler: function(message_level: level, message: string, logger_name: string, logger_log_level?: integer, ...: any)
   handler: function(log_level: logging.level, logger_name: string, message: string)
end

local LoggerBase: logging.Logger = {}
function LoggerBase:set_level(log_level: logging.level)
   self.current_level = logging.log_levels[log_level]
end

function LoggerBase:trace(message: string, ...: any)
   logging._logger_handler("TRACE", message, self.name, self.current_level, ...)
end

function LoggerBase:debug(message: string, ...: any)
   logging._logger_handler("DEBUG", message, self.name, self.current_level, ...)
end

function LoggerBase:info(message: string, ...: any)
   logging._logger_handler("INFO", message, self.name, self.current_level, ...)
end

function LoggerBase:warning(message: string, ...: any)
   logging._logger_handler("WARNING", message, self.name, self.current_level, ...)
end

function LoggerBase:error(message: string, ...: any)
   logging._logger_handler("ERROR", message, self.name, self.current_level, ...)
end

function LoggerBase:critical(message: string, ...: any)
   logging._logger_handler("CRITICAL", message, self.name, self.current_level, ...)
end

logging.loggers = {}
logging.logger_func = print
logging.current_level = 30
logging.log_levels = {
   ["TRACE"] = 0,
   ["DEBUG"] = 10,
   ["INFO"] = 20,
   ["WARNING"] = 30,
   ["ERROR"] = 40,
   ["CRITICAL"] = 50,
}

function logging.get_logger(name?: string): logging.Logger
   name = name or debug.getinfo(2, "S").short_src
   if logging.loggers[name] then
      return logging.loggers[name]
   end

   logging.loggers[name] = setmetatable({}, {__index=LoggerBase})
   logging.loggers[name].name = name

   return logging.loggers[name]
end

function logging.set_level(log_level: logging.level)
   logging.current_level = logging.log_levels[log_level]
end

function logging._logger_handler(message_level: logging.level, message: string, logger_name: string, logger_log_level?: integer, ...: any)
   local args = {...}
   for i, v in ipairs(args) do if type(v) == "table" then args[i] = cjson.encode(v as {string:any}) end end
   if logging.log_levels[message_level] >= (logger_log_level or logging.current_level) then
      logging.handler(message_level, logger_name, string.format(message, _unpack(args)))
   end
end

function logging.handler(log_level: logging.level, logger_name: string, message: string)
   local sec, usec = luv.gettimeofday()
   local current_time = os.date("%Y-%m-%d %H:%M:%S", sec) .. "." .. tostring(usec)
   logging.logger_func(string.format("%s %s [%s] %s", current_time, log_level, logger_name, message))
end

return logging
