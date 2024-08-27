
local record TraceEntry
   enum Level
      "ERROR"
      "WARNING"
      "INFO"
      "DEBUG"
      "TRACE"
   end

   record Source
      file: string
      line: integer
   end

   module: string
   level: TraceEntry.Level
   timestamp: integer -- unix timestamp in seconds
   time: number -- seconds since start of application
   fields: {string:any}

   message:string
end

return TraceEntry
