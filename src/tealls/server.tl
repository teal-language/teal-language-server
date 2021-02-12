
-- The global server state
-- Basically a singleton object to manage stuff like config loading
-- and the environment for type checking

local tl <const> = require("tl")
local config <const> = require("teal-cli.config")
local common <const> = require("teal-cli.tlcommon")

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
         change = 0,
         save = {
            includeText = true,
         },
      },
      hoverProvider = true,
   },
}

function server:get_env(): tl.Env
   if not self.config then
      return nil
   end
   -- applying the config to the env adds to package.path
   -- so lets reset them before doing that
   package.path = init_path
   package.cpath = init_cpath

   -- TODO: maintain some sort of persistent environment
   return common.apply_config_to_environment(self.config)
end

return server
