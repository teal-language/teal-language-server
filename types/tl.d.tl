
local record tl
   enum TypeName
      "typedecl"
      "typevar"
      "typearg"
      "function"
      "array"
      "map"
      "tupletable"
      "record"
      "interface"
      "self"
      "enum"
      "boolean"
      "string"
      "nil"
      "thread"
      "number"
      "integer"
      "union"
      "nominal"
      "emptytable"
      "literal_table_item"
      "unresolved_emptytable_value"
      "unresolved_typearg"
      "unresolvable_typearg"
      "circular_require"
      "boolean_context"
      "tuple"
      "poly"
      "any"
      "unknown"
      "invalid"
      "none"
      "*"
   end

   record TypeReporter
      typeid_to_num: {integer: integer}
      typename_to_num: {TypeName: integer}
      next_num: integer
      tr: TypeReport

      get_report: function(self):TypeReport
      get_typenum: function(self, Type): integer
   end

   -- interface Type
   record Type
      -- is Where
      -- where self.typename

      y: integer
      x: integer

      typename: TypeName    -- discriminator
      typeid: integer       -- unique identifier
      -- inferred_at: Where    -- for error messages
      needs_compat: boolean -- for Lua compatibilty
   end

   record StringType
      -- is Type
      -- where self.typename == "string"

      literal: string
   end

   enum Attribute
      "const"
      "close"
      "total"
   end

   enum Narrow
      "narrow"
      "narrowed_declaration"
      "localizing"
   end

   record Variable
      t: Type
      attribute: Attribute
      needs_compat: boolean
      narrowed_from: Type
      is_narrowed: Narrow
      declared_at: Node
      is_func_arg: boolean
      used: boolean
      used_as_type: boolean
      aliasing: Variable
      implemented: {string:boolean}
   end

   enum LoadMode
      "b"
      "t"
      "bt"
      "cb"
      "ct"
      "cbt"
   end
   type LoadFunction = function(...:any): any...

   enum GenCompat
      "off"
      "optional"
      "required"
   end

   enum GenTarget
      "5.1"
      "5.3"
      "5.4"
   end

   enum Feat
      "on"
      "off"
   end

   record GenerateOptions
      preserve_indent: boolean
      preserve_newlines: boolean
      preserve_hashbang: boolean
   end

   record CheckOptions
      feat_lax: Feat
      feat_arity: Feat
      gen_compat: GenCompat
      gen_target: GenTarget
      run_internal_compiler_checks: boolean
   end

   record Env
      globals: {string:Variable}
      modules: {string:Type}
      module_filenames: {string:string}
      loaded: {string:Result}
      loaded_order: {string}
      reporter: TypeReporter
      keep_going: boolean
      report_types: boolean
      defaults: CheckOptions
   end

   record Result
      filename: string
      ast: Node
      type: Type
      syntax_errors: {Error}
      type_errors: {Error}
      gen_error: string
      warnings: {Error}
      env: Env
      dependencies: {string:string} -- module name, file found
   end

   enum WarningKind
      "unknown"
      "unused"
      "redeclaration"
      "branch"
      "hint"
      "debug"
   end
   warning_kinds: {WarningKind:boolean}

   record Error
      y: integer
      x: integer
      msg: string
      filename: string

      tag: WarningKind

      -- used temporarily for stable-sorting
      i: integer
   end

   record Errors
      filename: string
      errors: {Error}
      warnings: {Error}
      unknown_dots: {string:boolean}
   end

   type errors = Errors

   typecodes: {string:integer}

   record TypeInfo
      t: integer

      str: string
      file: string
      x: integer
      y: integer
      ref: integer -- NOMINAL
      fields: {string: integer} -- RECORD
      enums: {string} -- ENUM
      args: {{integer, string}} -- FUNCTION
      rets: {{integer, string}} -- FUNCTION
      vararg: boolean -- FUNCTION
      varret: boolean -- FUNCTION
      types: {integer} -- UNION, POLY, TUPLE
      keys: integer -- MAP
      values: integer -- MAP
      elements: integer -- ARRAY
   end

   record TypeReport
      type Symbol = {integer, integer, string, integer}

      by_pos: {string: {integer: {integer: integer}}}
      types: {integer: TypeInfo}
      symbols: {Symbol}
      symbols_by_file: {string: {Symbol}}
      globals: {string: integer}
   end

   record EnvOptions
      defaults: CheckOptions
      predefined_modules: {string}
   end

   -- abstract type
   -- interface Node
   record Node
   end

   enum TokenKind
      "hashbang"
      "keyword"
      "op"
      "string"
      "[" "]" "(" ")" "{" "}" "," ":" "." ";" "?"
      "::"
      "..."
      "identifier"
      "number"
      "integer"
      "pragma"
      "pragma_identifier"
      "$ERR$"
      "$EOF$"
   end

   record Token
      x: integer
      y: integer
      tk: string
      kind: TokenKind
   end

   -----------------------------------------------------------------------------
   -- Public API
   -----------------------------------------------------------------------------

   check: function(Node, ? string, ? CheckOptions, ? Env): Result, string
   gen: function(string, ? Env, ? GenerateOptions): string, Result
   generate: function(ast: Node, gen_target: GenTarget, opts?: GenerateOptions): string, string
   get_token_at: function(tks: {Token}, y: integer, x: integer): string
   lex: function(input: string, filename: string): {Token}, {Error}
   load: function(string, ? string, ? LoadMode, ...: {any:any}): LoadFunction, string
   loader: function()
   new_env: function(? EnvOptions): Env, string
   parse: function(input: string, filename: string): Node, {Error}, {string}
   parse_program: function(tokens: {Token}, errs: {Error}, filename?: string): Node, {string}
   check_file: function(filename: string, env?: Env, fd?: FILE): (Result, string)
   check_string: function(input: string, env?: Env, filename?: string): Result
   search_module: function(module_name: string, search_dtl: boolean): string, FILE, {string}
   symbols_in_scope: function(tr: TypeReport, y: integer, x: integer, filename: string): {string:integer}
   target_from_lua_version: function(str: string): GenTarget
   version: function(): string

   -----------------------------------------------------------------------------
   -- Deprecated, mantained for backwards compatibility:
   -----------------------------------------------------------------------------

   type CompatMode = GenCompat
   type PrettyPrintOptions = GenerateOptions
   type TargetMode = GenTarget

   record TypeCheckOptions
      lax: boolean
      filename: string
      module_name: string
      gen_compat: tl.CompatMode
      gen_target: tl.TargetMode
      env: Env
      run_internal_compiler_checks: boolean
   end

   init_env: function(? boolean, ? boolean | tl.CompatMode, ? tl.TargetMode, ? {string}): Env, string
   pretty_print_ast: function(ast: Node, gen_target?: tl.TargetMode, mode?: boolean | tl.PrettyPrintOptions): string, string
   process: function(filename: string, env?: Env, fd?: FILE): Result, string
   process_string: function(input: string, is_lua: boolean, env: Env, filename: string, _module_name: string): Result
   type_check: function(Node, TypeCheckOptions): Result, string

   -----------------------------------------------------------------------------
   -- Private data:
   -----------------------------------------------------------------------------

   package_loader_env: Env
   load_envs: { {any:any} : Env }
end

return tl
