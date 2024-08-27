local _module_name = "path"

local asserts <const> = require("tea_leaves.asserts")
local class <const> = require("tea_leaves.class")
local util <const> = require("tea_leaves.util")
local tracing <const> = require("tea_leaves.tracing")
local uv <const> = require("luv")

local default_dir_permissions = tonumber('755', 8)

local record Path
   record WriteTextOpts
      overwrite: boolean
   end

   -- We make these read-only properties to ensure our path is immutable
   value:string

   _value:string

   record CreateDirectoryArgs
      parents:boolean
      exist_ok:boolean
   end

   metamethod __call: function(self: Path, value:string): Path
end

function Path:__init(value:string)
   asserts.that(value is string)
   asserts.that(#value > 0, "Path must be non empty string")

   self._value = value
end

function Path:is_valid():boolean
   local result = self._value:find("[" .. util.string_escape_special_chars("<>\"|?*") .. "]")
   return result == nil
end

function Path:get_value():string
   return self._value
end

function Path:__tostring():string
   -- return string.format("Path('%s')", self._value)
   return self._value
end

local function get_path_separator():string
   if util.get_platform() == "windows" then
      return "\\"
   end

   return "/"
end

local function _join(left:string, right:string):string
   if right == "." then
      return left
   end

   local combinedPath = left
   local lastCharLeft = left:sub(-1)

   local firstCharRight = right:sub(1, 1)
   local hasBeginningSlash = firstCharRight == '/' or firstCharRight == '\\'

   if lastCharLeft ~= '/' and lastCharLeft ~= '\\' then
      if not hasBeginningSlash then
         combinedPath = combinedPath .. get_path_separator()
      end
   else
      if hasBeginningSlash then
         right = right:sub(2, #right)
      end
   end

   combinedPath = combinedPath .. right
   return combinedPath
end

function Path:join(...:string):Path
   local args = {...}
   local result = self._value

   for _, value in ipairs(args) do
      result = _join(result, value)
   end

   return Path(result)
end

function Path:is_absolute():boolean
   if util.get_platform() == "windows" then
      return self._value:match('^[a-zA-Z]:[\\/]') ~= nil
   end

   return util.string_starts_with(self._value, '/')
end

function Path:is_relative():boolean
   return not self:is_absolute()
end

local function _remove_trailing_seperator_if_exists(path:string):string
   local result = path:match('^(.*[^\\/])[\\/]*$')
   asserts.is_not_nil(result, "Failed when processing path '{}'", path)
   return result
end

local function array_from_iterator<T>(itr:(function():T)):{T}
   local result = {}
   for value in itr do
      table.insert(result, value)
   end
   return result
end

function Path:get_parts():{string}
   if self._value == '/' then
      return {}
   end

   -- Remove the trailing seperator if it exists
   local fixed_value = _remove_trailing_seperator_if_exists(self._value)
   return array_from_iterator(string.gmatch(fixed_value, "([^\\/]+)"))
end

function Path:try_get_parent():Path
   if self._value == '/' then
      return nil
   end

   -- Remove the trailing seperator if it exists
   local temp_path = _remove_trailing_seperator_if_exists(self._value)

   -- If we have no seperators then there is no parent
   -- This works for both windows and linux since on windows temp_path is C: which returns nil
   if not temp_path:match('[\\/]') then
      return nil
   end

   -- We remove the trailing slash here because this is more likely
   -- to be the canonical form
   local parent_path_str = temp_path:match('^(.*)[\\/][^\\/]*$')

   if util.get_platform() ~= 'windows' and #parent_path_str == 0 then
      parent_path_str = "/"
   end

   return Path(parent_path_str)
end

function Path:get_parent():Path
   local result = self:try_get_parent()
   asserts.is_not_nil(result, "Expected to find parent but none was found for path '{}'", self._value)
   return result
end

function Path:get_parents():{Path}
   local result:{Path} = {}
   local parent = self:try_get_parent()
   if not parent then
      return result
   end
   table.insert(result, parent)
   parent = parent:try_get_parent()
   while parent do
      table.insert(result, parent)
      parent = parent:try_get_parent()
   end
   return result
end

function Path:get_file_name():string
   if self._value == "/" then
      return ""
   end

   local path = _remove_trailing_seperator_if_exists(self._value)

   if not path:match('[\\/]') then
      return path
   end

   return path:match('[\\/]([^\\/]*)$')
end

function Path:get_extension():string
   local result = self._value:match('%.([^%.]*)$')
   return result
end

function Path:get_file_name_without_extension():string
   local fileName = self:get_file_name()
   local extension = self:get_extension()

   if extension == nil then
      return fileName
   end

   return fileName:sub(0, #fileName - #extension - 1)
end

function Path:is_directory():boolean
   local stats = uv.fs_stat(self._value)
   return stats ~= nil and stats.type == "directory"
end

function Path:is_file():boolean
   local stats = uv.fs_stat(self._value)
   return stats ~= nil and stats.type == "file"
end

function Path:delete_empty_directory()
   asserts.that(self:is_directory())

   local success, error_message = pcall(uv.fs_rmdir, self._value)
   if not success then
      error(string.format("Failed to remove directory at '%s'. Details: %s", self._value, error_message))
   end
end

function Path:get_sub_paths():{Path}
   asserts.that(self:is_directory(), "Attempted to get sub paths for non directory path '{}'", self._value)

   local req, err = uv.fs_scandir(self._value)
   if req == nil then
      error(string.format("Failed to open dir '%s' for scanning.  Details: '%s'", self._value, err))
   end

   local function iter():string, string
      local r1, r2 = uv.fs_scandir_next(req)
      -- fs_scandir_next returns nil when its complete, but it also returns nil on failure,
      -- and then passes the error as second return value
      if not (r1 ~= nil or (r1 == nil and r2 == nil)) then
         error(string.format("Failure while scanning directory '%s': %s", self._value, r2))
      end
      return r1, r2
   end

   local result:{Path} = {}

   for name, _ in iter do
      table.insert(result, self:join(name))
   end

   return result
end

function Path:get_sub_directories():{Path}
   local result:{Path} = {}

   for _, sub_path in ipairs(self:get_sub_paths()) do
      if sub_path:is_directory() then
         table.insert(result, sub_path)
      end
   end

   return result
end

function Path:get_sub_files():{Path}
   local result:{Path} = {}

   for _, sub_path in ipairs(self:get_sub_paths()) do
      if sub_path:is_file() then
         table.insert(result, sub_path)
      end
   end

   return result
end

function Path:exists():boolean
   local stats = uv.fs_stat(self._value)
   return stats ~= nil
end

function Path:delete_file()
   asserts.that(self:is_file(), "Called delete_file for non-file at path '{}'", self._value)
   assert(uv.fs_unlink(self._value))
   tracing.trace(_module_name, "Deleted file at path '{path}'", {self._value})
end

function Path:create_directory(args:Path.CreateDirectoryArgs)
   if args and args.exist_ok and self:exists() then
      asserts.that(self:is_directory())
      return
   end

   if args and args.parents then
      local parent = self:try_get_parent()

      if not parent:exists() then
         parent:create_directory(args)
      end
   end

   local success, err = uv.fs_mkdir(self._value, default_dir_permissions)
   if not success then
      error(string.format("Failed to create directory '%s': %s", self._value, err))
   end
end

class.setup(Path, "Path", {
   getters = {
      value = "get_value",
   },
})

function Path.cwd():Path
   local cwd, err = uv.cwd()
   if cwd == nil then
      error(string.format("Failed to obtain current directory: %s", err))
   end
   return Path(cwd)
end

return Path

