
local tl <const> = require("tl")

local record TealProjectConfig
   build_dir: string
   source_dir: string
   include: {string}
   exclude: {string}
   global_env_def: string
   include_dir: {string}
   module_name: string
   scripts: {string:{string}}

   gen_compat: tl.CompatMode
   gen_target: tl.TargetMode
   disable_warnings: {tl.WarningKind}
   warning_error: {tl.WarningKind}

   -- externals field to allow for external tools to take entries in the config
   -- without our type checking complaining
   externals: {string:any}
end

return TealProjectConfig
