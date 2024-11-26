local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local tl = require("tl")

local Document = require("teal_language_server.document")

local lsp_formatter = {Documentation = {}, SignatureHelp = {SignatureParameter = {}, Signature = {}, }, }
























local function _split_not_in_parenthesis(str, start, finish)
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

function lsp_formatter.create_function_string(type_string, arg_names, tk)
   local _, _, types, args, returns = type_string:find("^function(.-)(%b())(.-)$")
   local output = {}
   if tk then output[1] = tk else output[1] = "function" end
   output[2] = types
   output[3] = "("

   for i, argument in ipairs(_split_not_in_parenthesis(args, 2, #args - 2)) do
      output[#output + 1] = arg_names[i]
      output[#output + 1] = ": "
      output[#output + 1] = argument
      output[#output + 1] = " "
   end
   output[#output] = ")"
   output[#output + 1] = returns
   return table.concat(output)
end













function lsp_formatter.show_type(node_info, type_info, doc)
   local output = { kind = "markdown" }
   local sb = { strings = {} }
   table.insert(sb.strings, "```teal")

   if type_info.t == tl.typecodes.FUNCTION then
      local args = doc:get_function_args_string(type_info)
      if args ~= nil then
         table.insert(sb.strings, "function " .. lsp_formatter.create_function_string(type_info.str, args, node_info.source))
      else
         table.insert(sb.strings, node_info.source .. ": " .. type_info.str)
      end

   elseif type_info.t == tl.typecodes.POLY then
      for i, type_ref in ipairs(type_info.types) do
         local func_info = doc:resolve_type_ref(type_ref)
         local args = doc:get_function_args_string(func_info)
         if args ~= nil then
            table.insert(sb.strings, "function " .. lsp_formatter.create_function_string(func_info.str, args, node_info.source))
         else
            local replaced_function = func_info.str:gsub("^function", node_info.source)
            table.insert(sb.strings, replaced_function)
         end
         if i < #type_info.types then
            table.insert(sb.strings, "```")
            table.insert(sb.strings, "or")
            table.insert(sb.strings, "```teal")
         end
      end

   elseif type_info.t == tl.typecodes.ENUM then
      table.insert(sb.strings, "enum " .. type_info.str)
      for _, _enum in ipairs(type_info.enums) do
         table.insert(sb.strings, '   "' .. _enum .. '"')
      end
      table.insert(sb.strings, "end")

   elseif type_info.t == tl.typecodes.RECORD then
      table.insert(sb.strings, "record " .. type_info.str)
      for key, type_ref in pairs(type_info.fields) do
         local type_ref_info = doc:resolve_type_ref(type_ref)
         table.insert(sb.strings, '   ' .. key .. ': ' .. type_ref_info.str)
      end
      table.insert(sb.strings, "end")

   else
      table.insert(sb.strings, node_info.source .. ": " .. type_info.str)
   end
   table.insert(sb.strings, "```")
   output.value = table.concat(sb.strings, "\n")
   return output
end

return lsp_formatter
