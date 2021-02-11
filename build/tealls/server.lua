local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local package = _tl_compat and _tl_compat.package or package




local tl = require("tl")
local config = require("teal-cli.config")
local common = require("teal-cli.tlcommon")

local server = {
   name = "teal-language-server",
   version = "dev",

   initialized = false,
   root_dir = nil,

   config = nil,

   capabilities = {

      textDocumentSync = {
         openClose = true,
         change = 0,
         save = {
            includeText = true,
         },
      },
      hoverProvider = true,
   },
}

local init_path = package.path
local init_cpath = package.cpath

function server:get_env()
   if not self.config then
      return nil
   end


   package.path = init_path
   package.cpath = init_cpath


   return common.apply_config_to_environment(self.config)
end

return server