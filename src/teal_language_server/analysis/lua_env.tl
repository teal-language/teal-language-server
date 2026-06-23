local _module_name = "analysis.lua_env"

local uv <const> = require("luv")
local util <const> = require("teal_language_server.util.util")
local logging <const> = require("teal_language_server.logging")

local logger = logging.get_logger(_module_name)

local record lua_env
end

-- Scan one level deep under workspace_root for any */bin/lua[.exe].
-- Returns the first match, or falls back to the system lua binary name.
function lua_env.find_lua_bin(workspace_root: string): string
   local bin_name = util.get_platform() == "windows" and "lua.exe" or "lua"

   local req = uv.fs_scandir(workspace_root)
   if req then
      while true do
         local name = uv.fs_scandir_next(req)
         if not name then break end
         local candidate = workspace_root .. "/" .. name .. "/bin/" .. bin_name
         local stat = uv.fs_stat(candidate)
         if stat ~= nil and stat.type == "file" then
            logger:debug("Found lua binary at %s", candidate)
            return candidate
         end
      end
   end

   logger:debug("No local lua binary found, falling back to system %s")
   return bin_name
end

-- Spawn lua_bin with an inline script that activates the luarocks loader (if
-- present) then writes package.path and package.cpath to stdout.  Returns the
-- two path strings, or nil, nil on any failure.
function lua_env.discover_paths(lua_bin: string): string, string
   local is_windows = util.get_platform() == "windows"

   -- Quote the binary so paths with spaces survive shell expansion.
   -- On Windows (cmd.exe) use double-quotes around the script; on Unix use
   -- single-quotes so the inner double-quotes reach Lua unmodified.
   local cmd: string
   if is_windows then
      cmd = '"' .. lua_bin .. '"' ..
         [[ -e "pcall(require,'luarocks.loader'); io.write(package.path..'\n'..package.cpath)"]]
   else
      cmd = '"' .. lua_bin .. '"' ..
         [[ -e 'pcall(require,"luarocks.loader"); io.write(package.path.."\n"..package.cpath)']]
   end

   logger:debug("Running lua path discovery: %s")

   local handle = io.popen(cmd)
   if not handle then
      logger:warning("Failed to open pipe to lua binary for path discovery")
      return nil, nil
   end

   local output = handle:read("*a")
   handle:close()

   if not output or #output == 0 then
      logger:warning("Lua binary produced no output during path discovery")
      return nil, nil
   end

   local path, cpath = output:match("^([^\n]*)\n([^\n]*)")
   if not path then
      logger:warning("Could not parse path discovery output: %s", output)
      return nil, nil
   end

   return path, cpath
end

return lua_env
