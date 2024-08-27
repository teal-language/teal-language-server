
local asserts <const> = require("tea_leaves.asserts")

local record args_parser
   enum LogMode
      "none"
      "by_date"
      "by_proj_path"
   end

   record CommandLineArgs
      verbose:boolean
      log_mode:LogMode
   end
end

function args_parser.parse_args():args_parser.CommandLineArgs
   local argparse = require("argparse")
   local parser = argparse("tea-leaves", "Tea Leaves")

   parser:option("-V --verbose", "")

   parser:option("-L --log-mode", "Specify approach to logging.  By default it is none which means no logging.  by_date names the file according to date.  by_proj_path names file according to the teal project path")
         :choices({"none", "by_date", "by_proj_path"})

   local raw_args = parser:parse()

   local verbose = raw_args["verbose"] as boolean
   local log_mode = raw_args["log_mode"] as args_parser.LogMode

   if log_mode == nil then
      log_mode = "none"
   else
      asserts.that(log_mode == "by_date" or log_mode == "by_proj_path")
   end

   local args:args_parser.CommandLineArgs = {
      verbose = verbose,
      log_mode = log_mode,
   }

   return args
end

return args_parser
