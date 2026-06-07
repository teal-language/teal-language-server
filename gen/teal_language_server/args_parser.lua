
local args_parser = { CommandLineArgs = {} }













function args_parser.parse_args()
   local argparse = require("argparse")
   local parser = argparse("teal-language-server", "Teal Language Server")

   parser:option("-V --verbose", "")


   parser:option("-L --log-mode", "Specify approach to logging.  By default it is none which means no logging.  by_date names the file according to date.  by_proj_path names file according to the teal project path"):
   choices({ "none", "by_date", "by_proj_path" })


   parser:flag("-C --coverage", "Enable luacov code coverage tracking (luacov must be installed; use 'luarocks test' or install it manually)"):hidden(true)

   local raw_args = parser:parse()

   local verbose = raw_args["verbose"]
   local log_mode = raw_args["log_mode"]
   local coverage = raw_args["coverage"]

   if log_mode == nil then
      log_mode = "none"
   end

   local args = {
      verbose = verbose,
      log_mode = log_mode,
      coverage = coverage,
   }

   return args
end

return args_parser
