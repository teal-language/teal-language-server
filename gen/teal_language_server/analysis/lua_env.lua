local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local io = _tl_compat and _tl_compat.io or io; local string = _tl_compat and _tl_compat.string or string; local _module_name = "analysis.lua_env"

local uv = require("luv")
local util = require("teal_language_server.util.util")
local logging = require("teal_language_server.logging")

local logger = logging.get_logger(_module_name)

local lua_env = {}




function lua_env.find_lua_bin(workspace_root)
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

   logger:debug("No local lua binary found, falling back to system %s", bin_name)
   return bin_name
end




function lua_env.discover_paths(lua_bin)
   local is_windows = util.get_platform() == "windows"




   local cmd
   if is_windows then
      cmd = '"' .. lua_bin .. '"' ..
      [[ -e "pcall(require,'luarocks.loader'); io.write(package.path..'\n'..package.cpath)"]]
   else
      cmd = '"' .. lua_bin .. '"' ..
      [[ -e 'pcall(require,"luarocks.loader"); io.write(package.path.."\n"..package.cpath)']]
   end

   logger:debug("Running lua path discovery: %s", cmd)

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
