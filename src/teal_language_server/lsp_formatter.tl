local tl <const> = require("tl")

local Document <const> = require("teal_language_server.document")

local record lsp_formatter
   record Documentation
      kind: string
      value: string
   end

   record SignatureHelp
      record SignatureParameter
         label: {integer, integer}
         documentation: Documentation
      end

      record Signature
         label: string
         parameters: {SignatureParameter}
         documentation: Documentation
         activeParameter: integer
      end

      signatures: {Signature}
      activeSignature: integer
      activeParameter: integer
   end
end

local function _split_not_in_parenthesis(str: string, start: integer, finish: integer): {string}
    local parens_count = 0
    local i = start
    local output = {}
    local start_field = i
    while i <= finish do
        if str:sub(i, i) == "(" then
            parens_count = parens_count + 1
        end
        if str:sub(i, i) == ")" then
            parens_count = parens_count - 1
        end
        if str:sub(i, i) == "," and parens_count == 0 then
            output[#output + 1] = str:sub(start_field, i)
            start_field = i + 2
        end
        i = i + 1
    end
    table.insert(output, str:sub(start_field, i))
    return output
end

function lsp_formatter.create_function_string(type_string: string, arg_names: {string}, tk?: string): string
   local _, _, types, args, returns = type_string:find("^function(.-)(%b())(.-)$") as (integer, integer, string, string, string)
   local output: {string} = {}
   if tk then output[1] = tk else output[1] = "function" end
   output[2] = types
   output[3] = "("

   for i, argument in ipairs(_split_not_in_parenthesis(args, 2, #args-2)) do
      output[#output+1] = arg_names[i]
      output[#output+1] = ": "
      output[#output+1] = argument
      output[#output+1] = " "
   end
   output[#output] = ")"
   output[#output+1] = returns
   return table.concat(output)
end

local record StringBuilder
   strings: {string}

   build: function(self): string = macroexp(self: StringBuilder): string
      return table.concat(self.strings, "\n")
   end

   add: function(self, line: string): nil = macroexp(self: StringBuilder, line: string): nil
      return table.insert(self.strings, line)
   end
end

function lsp_formatter.show_type(node_info: Document.NodeInfo, type_info: tl.TypeInfo, doc: Document): lsp_formatter.Documentation
   local output: lsp_formatter.Documentation = {kind="markdown"}
   local sb: StringBuilder = {strings = {}}
   sb:add("```teal")

   if type_info.t == tl.typecodes.FUNCTION then
      local args = doc:get_function_args_string(type_info)
      if args ~= nil then
         sb:add("function " .. lsp_formatter.create_function_string(type_info.str, args, node_info.source))
      else
         sb:add(node_info.source .. ": " .. type_info.str)
      end

   elseif type_info.t == tl.typecodes.POLY then
      for i, type_ref in ipairs(type_info.types) do
         local func_info = doc:resolve_type_ref(type_ref)
         local args = doc:get_function_args_string(func_info)
         if args ~= nil then
            sb:add("function " .. lsp_formatter.create_function_string(func_info.str, args, node_info.source))
         else
            local replaced_function = func_info.str:gsub("^function", node_info.source)
            sb:add(replaced_function)
         end
         if i < #type_info.types then
            sb:add("```")
            sb:add("or")
            sb:add("```teal")
         end
      end

   elseif type_info.t == tl.typecodes.ENUM then
      sb:add("enum " .. type_info.str)
      for _, _enum in ipairs(type_info.enums) do
         sb:add('   "' .. _enum .. '"')
      end
      sb:add("end")

   elseif type_info.t == tl.typecodes.RECORD then
      sb:add("record " .. type_info.str)
      for key, type_ref in pairs(type_info.fields) do
         local type_ref_info = doc:resolve_type_ref(type_ref)
         sb:add('   ' .. key .. ': ' .. type_ref_info.str)
      end
      sb:add("end")

   else
      sb:add(node_info.source .. ": " .. type_info.str)
   end
   sb:add("```")
   output.value = sb:build()
   return output
end

return lsp_formatter
