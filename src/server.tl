
-- The global server state
-- Basically a singleton object to manage stuff like config loading
-- and the environment for type checking

local tl <const> = require("tl")
local config <const> = require("cyan.config")
local common <const> = require("cyan.tlcommon")
local lsp <const> = require("tealls.lsp")

local init_path <const> = package.path
local init_cpath <const> = package.cpath

local server <const> = {
   name = "teal-language-server",
   version = "dev",

   initialized = false,
   root_dir: string = nil,

   config: config.Config = nil,

   capabilities = {
      -- we basically do the bare minimum
      textDocumentSync = {
         openClose = true,
         change = lsp.sync_kind.Full,
         save = {
            includeText = true,
         },
      },
      hoverProvider = true,
      definitionProvider = true,
      -- typeDefinitionProvider = true,
      -- completionProvider = {
         -- triggerCharacters = { ".", ":" },
      -- },
   },
}

function server:get_env(): tl.Env, string
   if not self.config then
      return nil
   end
   -- applying the config to the env adds to package.path
   -- so lets reset them before doing that
   package.path = init_path
   package.cpath = init_cpath

   -- TODO: maintain some sort of persistent environment
   return common.init_env_from_config(self.config)
end

return server
