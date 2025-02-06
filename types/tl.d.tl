
local record tl
   enum TypeName
      "generic"
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

   interface Where
      f: string
      y: integer
      x: integer
   end

   interface Type is Where where self.typename
      typename: TypeName    -- discriminator
      typeid: integer       -- unique identifier
      inferred_at: Where    -- for error messages
      needs_compat: boolean -- for Lua compatibilty
   end

   record GenericType is Type where self.typename == "generic"

      typeargs: {TypeArgType}
      t: FirstOrderType
      fresh: boolean
   end

   interface FirstOrderType is Type
   end

   type FirstClassType = GenericType | FirstOrderType

   interface StructuralType
      is FirstOrderType
   end

   record StringType is StructuralType where self.typename == "string"
      literal: string
   end

   -- interface NumericType is StructuralType where is_numeric_type(self)
   -- end

   -- record IntegerType is NumericType where self.typename == "integer"
   -- end

   record BooleanType
      is StructuralType
      where self.typename == "boolean"
   end

   -- This is a special internal type, to be used only as the node.expected
   -- type in boolean contexts such as `if _ then`. It behaves exactly like
   -- boolean except that type variables do not infer to it.
   record BooleanContextType
      is StructuralType
      where self.typename == "boolean_context"
   end

   record TypeDeclType
      is Type
      where self.typename == "typedecl"

      def: FirstClassType
      closed: boolean
      is_alias: boolean
      is_nested_alias: boolean
   end

   record LiteralTableItemType
      is Type
      where self.typename == "literal_table_item"

      -- table items
      kname: string
      ktype: FirstClassType
      vtype: FirstClassType
   end

   record Scope
      vars: {string:Variable}
      labels: {string:Node}
      pending_labels: {string:{Node}}
      pending_nominals: {string:{NominalType}}
      pending_global_types: {string:boolean}
      narrows: {string:boolean}
      is_transaction: boolean
   end

   interface HasDeclName
      declname: string
   end

   record NominalType
      is FirstOrderType
      where self.typename == "nominal"

      names: {string}
      typevals: {FirstClassType}
      found: TypeDeclType      -- type is found but typeargs are not resolved
      resolved: Type       -- type is found and typeargs are resolved
   end

   record SelfType
      is FirstOrderType
      where self.typename == "self"

      -- to be used only in error reports, not for type resolution
      display_type: RecordLikeType
   end

   interface ArrayLikeType
      is StructuralType
      where self.elements

      elements: Type
      consttypes: {Type}
      inferred_len: integer
   end

   record ArrayType
      is ArrayLikeType
      where self.typename == "array"
   end

   interface RecordLikeType
      is StructuralType, HasDeclName, ArrayLikeType
      where self.fields

      interface_list: {ArrayType | NominalType}
      interfaces_expanded: boolean
      fields: {string: Type}
      field_order: {string}
      meta_fields: {string: Type}
      meta_field_order: {string}
      is_userdata: boolean
   end

   record RecordType
      is RecordLikeType
      where self.typename == "record"
   end

   record InterfaceType
      is RecordLikeType
      where self.typename == "interface"
   end

   -- producing a new value of this type (not propagating)
   -- must always produce a type error
   record InvalidType
      is Type
      where self.typename == "invalid"
   end

   -- To be used in lax mode only:
   -- this represents non-annotated types in .lua files.
   record UnknownType
      is Type
      where self.typename == "unknown"
   end

   record TupleType
      is FirstOrderType
      where self.typename == "tuple"

      is_va: boolean
      tuple: {Type}
   end

   interface TypeArgType
      is Type
      where self.typename == "typearg"

      typearg: string
      constraint: Type
   end

   record UnresolvedTypeArgType
      is TypeArgType
      where self.typename == "unresolved_typearg"
   end

   record UnresolvableTypeArgType
      is Type
      where self.typename == "unresolvable_typearg"

      typearg: string
   end

   record TypeVarType
      is FirstOrderType
      where self.typename == "typevar"

      typevar: string
      constraint: Type
   end

   record MapType
      is StructuralType
      where self.typename == "map"

      keys: Type
      values: Type
   end

   record NilType
      is StructuralType
      where self.typename == "nil"
   end

   record EmptyTableType
      is Type
      where self.typename == "emptytable"

      declared_at: Node
      assigned_to: string
      keys: Type
   end

   record UnresolvedEmptyTableValueType
      is Type
      where self.typename == "unresolved_emptytable_value"

      emptytable_type: EmptyTableType
   end

   record FunctionType
      is StructuralType
      where self.typename == "function"

      is_method: boolean
      maybe_method: boolean
      is_record_function: boolean
      min_arity: integer
      args: TupleType
      rets: TupleType
      macroexp: Node
   end

   interface AggregateType
      is StructuralType
      where self.types

      types: {Type}
   end

   record UnionType
      is AggregateType
      where self.typename == "union"
   end

   record TupleTableType
      is AggregateType
      where self.typename == "tupletable"
   end

   -- Intersection types, currently restricted to polymorphic functions
   -- defined inside records, representing polymorphic Lua APIs.
   record PolyType
      is AggregateType
      where self.typename == "poly"

      types: {FunctionType | GenericType}
   end

   record EnumType
      is StructuralType, HasDeclName
      where self.typename == "enum"

      enumset: {string:boolean}
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
      used_as_type: boolean
      aliasing: Variable
      implemented: {string:boolean}
      has_been_read_from: boolean
      has_been_written_to: boolean
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
      "unread"
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

   enum NodeKind
      "op"
      "nil"
      "string"
      "number"
      "integer"
      "boolean"
      "literal_table"
      "literal_table_item"
      "function"
      "expression_list"
      "if"
      "if_block"
      "while"
      "fornum"
      "forin"
      "goto"
      "label"
      "repeat"
      "do"
      "break"
      "return"
      "newtype"
      "argument"
      "type_identifier"
      "variable"
      "variable_list"
      "statements"
      "assignment"
      "argument_list"
      "local_function"
      "global_function"
      "local_type"
      "global_type"
      "record_function"
      "local_declaration"
      "global_declaration"
      "identifier"
      "cast"
      "..."
      "paren"
      "macroexp"
      "local_macroexp"
      "interface"
      "pragma"
      "error_node"
   end

   interface Node is {Node}, Where where self.kind ~= nil
      kind: NodeKind
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

   enum ParseLang
      "lua"
      "tl"
   end

   check: function(Node, ? string, ? CheckOptions, ? Env): Result, string
   gen: function(string, ? Env, ? GenerateOptions): string, Result
   generate: function(ast: Node, gen_target: GenTarget, opts?: GenerateOptions): string, string
   get_token_at: function(tks: {Token}, y: integer, x: integer): string
   lex: function(input: string, filename: string): {Token}, {Error}
   load: function(string, ? string, ? LoadMode, ...: {any:any}): LoadFunction, string
   loader: function()
   new_env: function(? EnvOptions): Env, string
   parse: function(input: string, filename: string, parse_lang?: ParseLang): Node, {Error}, {string}
   parse_program: function(tokens: {Token}, errs: {Error}, filename?: string, parse_lang?: ParseLang): Node, {string}
   check_file: function(filename: string, env?: Env, fd?: FILE): (Result, string)
   check_string: function(input: string, env?: Env, filename?: string, parse_lang?: ParseLang): Result
   search_module: function(module_name: string, search_dtl: boolean): string, FILE, {string}
   symbols_in_scope: function(tr: TypeReport, y: integer, x: integer, filename: string): {string:integer}
   target_from_lua_version: function(str: string): GenTarget
   version: function(): string

   -----------------------------------------------------------------------------
   -- Deprecated, mantained for backwards compatibility:
   -----------------------------------------------------------------------------

   -- type CompatMode = GenCompat
   -- type PrettyPrintOptions = GenerateOptions
   -- type TargetMode = GenTarget

   -- record TypeCheckOptions
   --    lax: boolean
   --    filename: string
   --    module_name: string
   --    gen_compat: tl.CompatMode
   --    gen_target: tl.TargetMode
   --    env: Env
   --    run_internal_compiler_checks: boolean
   -- end

   -- init_env: function(? boolean, ? boolean | tl.CompatMode, ? tl.TargetMode, ? {string}): Env, string
   -- pretty_print_ast: function(ast: Node, gen_target?: tl.TargetMode, mode?: boolean | tl.PrettyPrintOptions): string, string
   -- process: function(filename: string, env?: Env, fd?: FILE): Result, string
   -- process_string: function(input: string, is_lua: boolean, env: Env, filename: string, _module_name: string): Result
   -- type_check: function(Node, TypeCheckOptions): Result, string

   -----------------------------------------------------------------------------
   -- Private data:
   -----------------------------------------------------------------------------

   -- package_loader_env: Env
   -- load_envs: { {any:any} : Env }
end

return tl
