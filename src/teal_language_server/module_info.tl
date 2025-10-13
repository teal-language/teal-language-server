local _module_name = "module_info"

-- <imports>
local tracing <const> = require("teal_language_server.tracing")
local asserts <const> = require("teal_language_server.asserts")
local tl <const> = require("tl")
local class <const> = require("teal_language_server.class")
local Uri <const> = require("teal_language_server.uri")
local ltreesitter <const> = require("ltreesitter")
local teal_parser = ltreesitter.require("parser/teal", "teal")

local record ModuleInfo
   path: string
   module_name: string
   ast: tl.Node
   tokens: {tl.Token}
   err_tokens: {tl.Error}
   parse_errors: {tl.Error}
   content: string
   required_modules: {string}
   hash: integer
   modification_time: integer
   dependencies: {string: boolean}  -- List of file paths this file depends on
   dependents: {string: boolean}  -- List of file paths this file depends on
   check_result: tl.Result
   uri: Uri
   tree: ltreesitter.Tree
   tree_cursor: ltreesitter.Cursor
   is_opened: boolean
   requires_build: boolean

   _module_name: string
   _path: string
   _tokens: {tl.Token}
   _err_tokens: {tl.Error}
   _ast: tl.Node
   _parse_errors: {tl.Error}
   _content: string
   _required_modules: {string}
   _hash: integer
   _tree: ltreesitter.Tree
   _tree_cursor: ltreesitter.Cursor

   metamethod __call: function(self: ModuleInfo, path: string, module_name: string): ModuleInfo
end

function ModuleInfo:__init(path: string, module_name: string)
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

   -- Note that check_result is controlled elsewhere
end

local function slow_hash(str:string): integer
    local hash = 2166136261
    for i = 1, #str do
        local byte = string.byte(str, i)
        -- XOR without bitwise operators
        hash = hash - (hash % 256) + ((hash + byte) % 256)
        hash = (hash * 16777619) % 4294967296
    end
    return hash
end

function ModuleInfo:try_update_content(content: string): boolean
   local new_hash: integer

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

   if #self._err_tokens > 0 then
      return
   end

   asserts.is_not_nil(self._tokens)

   self._parse_errors = {}
   self._ast, self._required_modules = tl.parse_program(self._tokens, self._parse_errors, self._path)
   asserts.is_not_nil(self._ast)
   asserts.is_not_nil(self._required_modules)
   tracing.trace(_module_name, "parse_prog errors: {}", {#self._parse_errors})
end

class.setup(ModuleInfo, "ModuleInfo",  {
   getters = {
      path = function(self: ModuleInfo): string
         return self._path
      end,
      module_name = function(self: ModuleInfo): string
         return self._module_name
      end,
      tokens = function(self: ModuleInfo): {tl.Token}
         self:_lazy_update_tokens()
         asserts.is_not_nil(self._tokens)
         return self._tokens
      end,
      ast = function(self: ModuleInfo): tl.Node
         self:_lazy_update_ast()
         asserts.is_not_nil(self._ast)
         return self._ast
      end,
      err_tokens = function(self: ModuleInfo): {tl.Error}
         self:_lazy_update_tokens()
         asserts.is_not_nil(self._err_tokens)
         return self._err_tokens
      end,
      parse_errors = function(self: ModuleInfo): {tl.Error}
         self:_lazy_update_ast()
         asserts.is_not_nil(self._parse_errors)
         return self._parse_errors
      end,
      content = function(self: ModuleInfo): string
         return self._content
      end,
      required_modules = function(self: ModuleInfo): {string}
         self:_lazy_update_ast()
         asserts.is_not_nil(self._required_modules)
         return self._required_modules
      end,
      hash = function(self: ModuleInfo): integer
         asserts.is_not_nil(self._hash)
         return self._hash
      end,
      tree = function(self: ModuleInfo): ltreesitter.Tree
         self:_lazy_update_treesitter()
         return self._tree
      end,
      tree_cursor = function(self: ModuleInfo): ltreesitter.Cursor
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
   }
})
return ModuleInfo
