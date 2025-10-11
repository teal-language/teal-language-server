local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local string = _tl_compat and _tl_compat.string or string; local _module_name = "module_info"


local tracing = require("teal_language_server.tracing")
local asserts = require("teal_language_server.asserts")
local tl = require("tl")
local class = require("teal_language_server.class")
local Uri = require("teal_language_server.uri")
local ltreesitter = require("ltreesitter")
local teal_parser = ltreesitter.require("parser/teal", "teal")

local ModuleInfo = {}


































function ModuleInfo:__init(path, module_name)
   self._path = path
   self._module_name = module_name
   self.dependents = {}
   self.dependencies = {}
   self._hash = 0
   self.is_opened = false
   self.requires_build = true
end

function ModuleInfo:clear_teal_cache()
   self._tokens = nil
   self._err_tokens = nil
   self._ast = nil
   self._parse_errors = nil
   self._required_modules = nil


end

local function slow_hash(str)
   local hash = 2166136261
   for i = 1, #str do
      local byte = string.byte(str, i)

      hash = hash - (hash % 256) + ((hash + byte) % 256)
      hash = (hash * 16777619) % 4294967296
   end
   return hash
end

function ModuleInfo:try_update_content(content)
   local new_hash

   if content == nil then
      new_hash = 0
   else
      new_hash = slow_hash(content)
      asserts.is_not_nil(new_hash)
   end

   if new_hash == self._hash then
      return false
   end

   self:clear_teal_cache()
   self._hash = new_hash
   self._content = content
   self._tree = nil
   self._tree_cursor = nil

   return true
end

function ModuleInfo:_lazy_update_tokens()
   if self._tokens then
      return
   end

   asserts.is_not_nil(self._content)
   self._tokens, self._err_tokens = tl.lex(self._content, self._path)
   if not self._err_tokens then
      self._err_tokens = {}
   end
end

function ModuleInfo:_lazy_update_treesitter()
   if self._tree then
      return
   end

   asserts.is_not_nil(self._content)
   self._tree = teal_parser:parse_string(self._content)
   asserts.is_not_nil(self._tree)
   self._tree_cursor = self._tree:root():create_cursor()
end

function ModuleInfo:_lazy_update_ast()
   if self._ast then
      return
   end

   self:_lazy_update_tokens()
   asserts.is_not_nil(self._tokens)

   self._parse_errors = {}
   self._ast, self._required_modules = tl.parse_program(self._tokens, self._parse_errors, self._path)
   asserts.is_not_nil(self._ast)
   asserts.is_not_nil(self._required_modules)
   tracing.trace(_module_name, "parse_prog errors: {}", { #self._parse_errors })
end

class.setup(ModuleInfo, "ModuleInfo", {
   getters = {
      path = function(self)
         return self._path
      end,
      module_name = function(self)
         return self._module_name
      end,
      tokens = function(self)
         self:_lazy_update_tokens()
         asserts.is_not_nil(self._tokens)
         return self._tokens
      end,
      ast = function(self)
         self:_lazy_update_ast()
         asserts.is_not_nil(self._ast)
         return self._ast
      end,
      err_tokens = function(self)
         self:_lazy_update_tokens()
         asserts.is_not_nil(self._err_tokens)
         return self._err_tokens
      end,
      parse_errors = function(self)
         self:_lazy_update_ast()
         asserts.is_not_nil(self._parse_errors)
         return self._parse_errors
      end,
      content = function(self)
         return self._content
      end,
      required_modules = function(self)
         self:_lazy_update_ast()
         asserts.is_not_nil(self._required_modules)
         return self._required_modules
      end,
      hash = function(self)
         asserts.is_not_nil(self._hash)
         return self._hash
      end,
      tree = function(self)
         self:_lazy_update_treesitter()
         return self._tree
      end,
      tree_cursor = function(self)
         self:_lazy_update_treesitter()
         return self._tree_cursor
      end,
   },
   nilable_members = {
      '_tokens',
      '_err_tokens',
      '_ast',
      '_parse_errors',
      '_result',
      '_content',
      '_required_modules',
      'modification_time',
      'dependencies',
      'check_result',
      'uri',
      '_tree',
      '_tree_cursor',
   },
})
return ModuleInfo
