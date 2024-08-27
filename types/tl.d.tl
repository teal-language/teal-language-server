
local record tl
   enum LoadMode
      "b"
      "t"
      "bt"
      "cb"
      "ct"
      "cbt"
   end
   type LoadFunction = function(...:any): any...

   enum CompatMode
      "off"
      "optional"
      "required"
   end

   enum TargetMode
      "5.1"
      "5.3"
      "5.4"
   end

   record TypeCheckOptions
      lax: boolean
      filename: string
      module_name: string
      gen_compat: CompatMode
      gen_target: TargetMode
      env: Env
      run_internal_compiler_checks: boolean
   end

   enum Attribute
      "const"
      "close"
      "total"
   end

   record Type
      {Type}
      y: integer
      x: integer
      filename: string
      typename: TypeName
      tk: string

      yend: integer
      xend: integer

      -- Lua compatibilty
      needs_compat: boolean

      -- tuple
      is_va: boolean

      -- poly, union, tupletable
      types: {Type}

      -- typetype
      def: Type
      is_alias: boolean
      closed: boolean

      -- map
      keys: Type
      values: Type
      is_total: boolean
      missing: {string}

      -- records
      typeargs: {Type}
      fields: {string: Type}
      field_order: {string}
      meta_fields: {string: Type}
      meta_field_order: {string}
      is_userdata: boolean

      -- array
      elements: Type
      -- tupletable/array
      inferred_len: integer

      -- function
      is_method: boolean
      args: Type
      rets: Type

      typeid: integer

      -- function argument
      is_self: boolean

      -- nominal
      names: {string}
      typevals: Type
      found: Type    -- type is found but typeargs are not resolved
      resolved: Type -- type is found and typeargs are resolved

      -- typevar
      typevar: string

      -- typearg
      typearg: string

      -- table items
      kname: string
      ktype: Type
      vtype: Type

      -- emptytable
      declared_at: Node
      assigned_to: string
      keys_inferred_at: Node
      keys_inferred_at_file: string
      inferred_at: Node
      inferred_at_file: string
      emptytable_type: Type

      -- enum
      enumset: {string:boolean}

      -- unresolved items
      labels: {string:{Node}}
      nominals: {string:{Type}}
      global_types: {string:boolean}
      narrows: {string:boolean}
   end

   enum FactType
      "is"     -- type-based type judgement (its negation implies the subtracted type)
      "=="     -- value-based type judgement (its negation does not imply a subtracted type negated)
      "not"    -- negation: type-based judgements subtract, value-based judgements prove nothing
      "and"    -- conjunction: type-based judgements intersect, any value-based judgement downgrades all
      "or"     -- disjunction: type-based judgements unite, any value-based judgement downgrades all
      "truthy" -- expression that is either truthy or a runtime error
   end

   record Fact
      fact: FactType
      where: Node

      -- is
      var: string
      typ: Type

      -- not, and, or
      f1: Fact
      f2: Fact

      metamethod __call: function(Fact, Fact): Fact
   end

   enum TokenKind
      "keyword"
      "op"
      "string"
      "[" "]" "(" ")" "{" "}" "," ":" "#" "." ";"
      "::"
      "..."
      "identifier"
      "number"
      "integer"
      "$ERR unfinished_comment$"
      "$ERR invalid_string$"
      "$ERR invalid_number$"
      "$ERR invalid$"
      "$EOF$"
   end

   record Token
      x: integer
      y: integer
      tk: string
      kind: TokenKind
   end

   record PrettyPrintOpts
      preserve_indent: boolean
      preserve_newlines: boolean
   end

   enum Narrow
      "narrow"
      "narrowed_declaration"
      "declaration"
   end

   record Operator
      y: integer
      x: integer
      arity: integer
      op: string
      prec: integer
   end

   enum KeyParsed
      "short"
      "long"
      "implicit"
   end

   enum NodeKind
      "op"
      "nil"
      "string"
      "number"
      "integer"
      "boolean"
      "table_literal"
      "table_item"
      "function"
      "expression_list"
      "enum_item"
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
      "error_node"
   end

   record Node
      {Node}

      record ExpectedContext
         kind: NodeKind
         name: string
      end

      y: integer
      x: integer
      tk: string
      kind: NodeKind
      symbol_list_slot: integer
      semicolon: boolean

      is_longstring: boolean

      yend: integer
      xend: integer

      known: Fact

      -- bidirectional inference
      expected: Type
      expected_context: Node.ExpectedContext

      key: Node
      value: Node
      key_parsed: KeyParsed

      typeargs: Type
      args: Node
      rets: Type
      body: Node
      implicit_global_function: boolean
      is_predeclared_local_function: boolean
      rtype: Type

      name: Node

      -- statements list in a `repeat`, delay closing scope
      is_repeat: boolean

      -- var declaration
      attribute: Attribute

      fn_owner: Node
      is_method: boolean

      exp: Node
      if_parent: Node
      if_block_n: integer
      if_blocks: {Node}
      block_returns: boolean

      -- fornum
      var: Node
      from: Node
      to: Node
      step: Node

      -- forin
      vars: Node
      exps: Node

      -- newtype
      newtype: Type
      is_alias: boolean
      elide_type: boolean

      -- expressions
      op: Operator
      e1: Node
      e2: Node
      constnum: number
      conststr: string
      failstore: boolean

      -- table literal
      array_len: integer

      -- goto
      label: string

      casttype: Type

      -- variable
      is_lvalue: boolean

      type: Type
      decltype: Type
   end

   enum TypeName
      "typetype"
      "nestedtype"
      "typevar"
      "typearg"
      "function"
      "array"
      "map"
      "tupletable"
      "arrayrecord"
      "record"
      "enum"
      "boolean"
      "string"
      "nil"
      "thread"
      "number"
      "integer"
      "union"
      "nominal"
      "bad_nominal"
      "emptytable"
      "table_item"
      "unresolved_emptytable_value"
      "unresolved_typearg"
      "unresolvable_typearg"
      "circular_require"
      "tuple"
      "poly" -- intersection types, currently restricted to polymorphic functions defined inside records
      "any"
      "unknown" -- to be used in lax mode only
      "invalid" -- producing a new value of this type (not propagating) must always produce a type error
      "unresolved"
      "none"
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

   record Env
      globals: {string:Variable}
      modules: {string:Type}
      loaded: {string:Result}
      loaded_order: {string}
      gen_compat: CompatMode
      gen_target: TargetMode
      keep_going: boolean
   end

   record Symbol
      x: integer
      y: integer
      name: string
      typ: Type
      other: integer
      skip: boolean
   end

   record Result
      filename: string
      ast: Node
      type: Type
      syntax_errors: {Error}
      type_errors: {Error}
      gen_error: string
      warnings: {Error}
      symbol_list: {Symbol}
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

   typecodes: {string:integer}

   record TypeInfo
      t: integer

      str: string
      file: string
      x: integer
      y: integer
      ref: integer -- NOMINAL
      fields: {string: integer} -- RECORD, ARRAYRECORD
      enums: {string} -- ENUM
      args: {{integer, string}} -- FUNCTION
      rets: {{integer, string}} -- FUNCTION
      vararg: boolean -- FUNCTION
      types: {integer} -- UNION, POLY, TUPLE
      keys: integer -- MAP
      values: integer -- MAP
      elements: integer -- ARRAY
   end

   record TypeReport
      by_pos: {string: {integer: {integer: integer}}}
      types: {integer: TypeInfo}
      symbols: {{integer, integer, string, integer}}
      globals: {string: integer}
   end

   record TypeReportEnv
      typeid_to_num: {integer: integer}
      next_num: integer
      tr: TypeReport
   end

   load: function(input: string, chunkname: string, mode: LoadMode, ...: {any:any}): LoadFunction, string
   process: function(filename: string, env: Env, module_name: string, fd: FILE): Result, string
   process_string: function(string, boolean, Env, string, string): Result
   gen: function(input: string, env: Env): string, Result
   type_check: function(ast: Node, opts: TypeCheckOptions): Result, string
   init_env: function(lax: boolean, gen_compat: boolean | CompatMode, gen_target: TargetMode, predefined: {string}): Env, string
   version: function(): string

   package_loader_env: Env
   load_envs: { {any:any} : Env }

   lex: function(input: string, filename: string): {Token}, {Error}
   get_token_at: function(tks: {Token}, y: integer, x: integer): string
   parse_program: function(tokens: {Token}, errs: {Error}, filename: string): Node, {string}
   parse: function(input: string, filename: string): Node, {Error}, {string}
   pretty_print_ast: function(ast: Node, gen_target: TargetMode, mode: boolean | PrettyPrintOpts): string, string
   search_module: function(module_name: string, search_dtl: boolean): string, FILE, {string}
   get_types: function(result: Result, trenv: TypeReportEnv): TypeReport, TypeReportEnv
   symbols_in_scope: function(tr: TypeReport, y: integer, x: integer): {string:integer}
   process_string: function(input: string, is_lua: boolean, env: Env, filename: string, module_name: string): Result
   loader: function()
   target_from_lua_version: function(str: string): TargetMode
end

return tl
