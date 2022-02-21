local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local package = _tl_compat and _tl_compat.package or package




local tl = require("tl")
local config = require("cyan.config")
local common = require("cyan.tlcommon")
local lsp = require("tealls.lsp")

local init_path = package.path
local init_cpath = package.cpath

local server = {
   name = "teal-language-server",
   version = "dev",

   initialized = false,
   root_dir = nil,

   config = nil,

   capabilities = {

      textDocumentSync = {
         openClose = true,
         change = lsp.sync_kind.Full,
         save = {
            includeText = true,
         },
      },
      hoverProvider = true,
      definitionProvider = true,

      completionProvider = {
         triggerCharacters = { ".", ":" },
      },
   },
}

function server:get_env()
   if not self.config then
      return nil
   end


   package.path = init_path
   package.cpath = init_cpath


   return common.init_env_from_config(self.config)
end

return server