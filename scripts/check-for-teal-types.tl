local deps: {string} = {
   "https://raw.githubusercontent.com/teal-language/teal-types/master/types/dkjson/dkjson.d.tl",
   "https://raw.githubusercontent.com/teal-language/teal-types/master/types/luafilesystem/lfs.d.tl",
}

local fs <const> = require("cyan.fs")
local log <const> = require("cyan.log")
local cs <const> = require("cyan.colorstring")
local ansi <const> = require("cyan.ansi")

local types_path <const> = fs.path.new("types")

local dep_info <const> = log.create_logger(io.stdout, "normal", cs.highlight(cs.colors.teal, "Dep Info"), cs.highlight(cs.colors.teal, "..."))
local dep_warn <const> = log.create_logger(io.stderr, "normal", cs.highlight(cs.colors.warn, "Dep Warn"), cs.highlight(cs.colors.warn, "..."))
local dep_err <const> = log.create_logger(io.stderr, nil, cs.highlight(cs.colors.error, "Dep Warn"), cs.highlight(cs.colors.error, "..."))
local dep_extra <const> = log.create_logger(io.stderr, "extra", cs.highlight(cs.colors.teal, "Dep *Info"), cs.highlight(cs.colors.teal, "..."))

if os.getenv("TLS_DONT_CHECK_DEPS") then
   dep_extra("TLS_DONT_CHECK_DEPS environment variable is defined, not checking for teal-types dependencies")
   return
end

local force_update <const> = os.getenv("TLS_FORCE_UPDATE_DEPS") ~= nil
local cmd_str <const> = os.getenv("TLS_FETCH_CMD") or "wget -O %FILE% %URL%"

do
   local not_defined = cs.highlight({ ansi.color.bright.black }, "not defined"):tostring()
   dep_extra(
      "Relevant environment variables:\n"
      .. "     TLS_DONT_CHECK_DEPS = ", os.getenv("TLS_DONT_CHECK_DEPS") or not_defined, "\n"
      .. "   TLS_FORCE_UPDATE_DEPS = ", os.getenv("TLS_FORCE_UPDATE_DEPS") or not_defined, "\n"
      .. "           TLS_FETCH_CMD = ", os.getenv("TLS_FETCH_CMD") or not_defined, "\n"
      .. "                 default = wget -O %FILE% %URL%\n"
      .. "\nIn TLS_FETCH_CMD, %FILE% and %URL% get substituted with the desired file and url when running the command."
   )
end

local function display_filename(f: fs.Path): cs.ColorString
   return cs.highlight(cs.colors.file, f:tostring())
end

if not types_path:exists() then
   dep_warn("Directory ", display_filename(types_path), " does not exist, attempting to create it")
   local ok <const>, err <const> = types_path:mkdir()
   if not ok then
      dep_err("Unable to create directory ", display_filename(types_path), ":\n   ", err)
      os.exit(1)
   end
   dep_extra("Created directory ", display_filename(types_path))
elseif not types_path:is_directory() then
   dep_err(display_filename(types_path), " was expected to be a directory, but is not")
   os.exit(1)
end

-- types_path exists and is a directory

local record FetchPair
   destination: fs.Path
   url: string
end
local to_be_fetched <const>: {FetchPair} = {}
local missing_str <const>: {string} = { "Missing dependencies:" }

for _, dep in ipairs(deps) do
   local result_path = types_path:copy()
   result_path:append(dep:match("[^/]+$"))

   if force_update or not result_path:exists() then
      table.insert(to_be_fetched, { destination = result_path, url = dep })
      table.insert(missing_str, display_filename(result_path):tostring() .. " from " .. dep)
   end
end

if #to_be_fetched == 0 then
   return
end

-- TODO: cyan should probably provide a script_utils module with stuff like this
local function yes_no_prompt(prompt: string, default: boolean): boolean
   local y <const> = cs.highlight({ ansi.color.dark.green }, default and "Y" or "y")
   local n <const> = cs.highlight({ ansi.color.dark.red }, default and "n" or "N")
   local prompt_str <const> = prompt .. " [" .. y:tostring() .. "/" .. n:tostring() .. "]: "

   while true do
      io.write(prompt_str)
      io.flush()
      local input = io.read("*l"):lower()

      if #input == 0 then
         return default
      end

      local yes <const>: {string:boolean} = {
         ["yes"] = true,
         ["ye"] = true,
         ["y"] = true,
      }

      local no <const>: {string:boolean} = {
         ["no"] = true,
         ["n"] = true,
      }

      if yes[input] then
         return true
      elseif no[input] then
         return false
      end
   end
end

dep_warn(table.concat(missing_str, "\n   "))

if not yes_no_prompt("Download dependencies?", true) then
   dep_warn([[Not downloading dependencies

You will need to download them manually to the expected paths or have them in
your LUA_PATH. If they are already in your LUA_PATH, set the
TLS_DONT_CHECK_DEPS environment variable to skip running this script.]])
   os.exit(1)
end

local dep_cmd <const> = log.create_logger(io.stdout, "normal", cs.highlight(cs.colors.teal, "Cmd Out"), cs.highlight(cs.colors.teal, "..."))
local dep_cmd_cont <const> = log.create_logger(io.stdout, "normal", cs.highlight(cs.colors.teal, "..."))

local function run_cmd(cmd: string, max_log_lines: integer): boolean, integer, {string}
	max_log_lines = max_log_lines or math.huge as integer
   local display_cmd = cs.highlight({ansi.color.dark.magenta}, cmd)
   dep_info("Running command ", display_cmd)
   local p <const>, popen_err <const> = io.popen(cmd)
   if not p then
      dep_err("Failed to run command ", display_cmd, "\n   ", popen_err)
      return false
   end
	local res <const>: {string} = {}
	local ln = p:read("*l")
	while ln do
		if #res < max_log_lines then
			if res[1] then
				dep_cmd_cont("   ", ln)
			else
				dep_cmd("   ", ln)
			end
      elseif #res == max_log_lines then
         dep_cmd_cont("   ", cs.highlight({ ansi.color.bright.black }, "... (truncated)"))
		end
		table.insert(res, ln)
		ln = p:read("*l")
	end
	local ok <const>, pclose_err <const>, exit_code <const> = p:close() as (boolean, string, integer)

   if not ok or exit_code ~= 0 then
      local out_filename = "dep-cmd-output.txt"
      local written = ""
      local f <const> = io.open(out_filename, "w")
      if f then
         f:write(table.concat(res, "\n"))
         f:close()
         written = "\n   Command output written to " .. display_filename(fs.path.new(out_filename)):tostring()
      end

      dep_err("Command ", display_cmd, " exited abnormally (with exit code ", exit_code, ")", written)
      return false, exit_code
   end

	return true, exit_code, res
end

for _, dep in ipairs(to_be_fetched) do
   local cmd <const> = cmd_str:gsub("%%%w+%%", function(match: string): string
      if match == "%URL%" then
         return dep.url
      elseif match == "%FILE%" then
         return dep.destination:to_real_path()
      end
      return match
   end)
   if not run_cmd(cmd) then
      os.exit(1)
   end
end
