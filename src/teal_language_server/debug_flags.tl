
local record debug_flags
   extra_debugging_enabled: boolean
   trace_modules: {string}
   quit_on_error: boolean
end

-- debug_flags.trace_modules =  {
--    "env_manager",
--    "diagnostics_helper"
-- }
-- debug_flags.extra_debugging_enabled = true
-- debug_flags.quit_on_error = true

debug_flags.trace_modules = {}
debug_flags.extra_debugging_enabled = false
debug_flags.quit_on_error = false

return debug_flags
