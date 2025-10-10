
local record debug_flags
   extra_debugging_enabled: boolean
   trace_modules: {string}
end

debug_flags.trace_modules =  {
   -- "env_manager",
   -- "diagnostics_helper"
}
debug_flags.extra_debugging_enabled = false

-- debug_flags.extra_debugging_enabled = false
-- debug_flags.trace_modules = {}

return debug_flags
