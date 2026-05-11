
local record debug_flags
   extra_debugging_enabled: boolean
   default_trace_modules: {string}
   quit_on_error: boolean
end

debug_flags.default_trace_modules =  {
}
debug_flags.extra_debugging_enabled = false
debug_flags.quit_on_error = false

return debug_flags
