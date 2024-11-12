local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local tl = require("tl")

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

local function indent(n)
   return ("   "):rep(n)
end
local function ti(list, ...)
   for i = 1, select("#", ...) do
      table.insert(list, (select(i, ...)))
   end
end


function lsp_formatter.show_type(info, tr, depth)
   if not info then return "???" end
   depth = depth or 1
   if depth > 4 then
      return "..."
   end

   local out = {}

   local function ins(...)
      ti(out, ...)
   end

   local function show_record_field(name, field_id)
      local field = {}
      ti(field, indent(depth))
      local field_type = tr.types[field_id]
      if field_type.str:match("^type ") then
         ti(field, "type ", name, " = ", (lsp_formatter.show_type(field_type, tr, depth + 1):gsub("^type ", "")))
      else
         ti(field, name, ": ", lsp_formatter.show_type(field_type, tr, depth + 1))
      end
      ti(field, "\n")
      return table.concat(field)
   end

   local function show_record_fields(fields)
      if not fields then
         ins("--???\n")
         return
      end
      local f = {}
      for name, field_id in pairs(fields) do
         ti(f, show_record_field(name, field_id))
      end
      local function get_name(s)
         return (s:match("^%s*type ([^=]+)") or s:match("^%s*([^:]+)")):lower()
      end
      table.sort(f, function(a, b)
         return get_name(a) < get_name(b)
      end)
      for _, field in ipairs(f) do
         ins(field)
      end
   end

   if info.ref then
      return info.str .. " => " .. lsp_formatter.show_type(tr.types[info.ref], tr, depth + 1)
   elseif info.t == tl.typecodes.RECORD then
      ins(info.str)
      if not info.fields then
         ins(" ??? end")
         return table.concat(out)
      end
      ins("\n")
      show_record_fields(info.fields)
      ins(indent(depth - 1))
      ins("end")
      return table.concat(out)
   elseif info.t == tl.typecodes.ENUM then
      ins("enum\n")
      if info.enums then
         for _, str in ipairs(info.enums) do
            ins(indent(depth))
            ins(string.format("%q\n", str))
         end
      else
         ins(indent(depth))
         ins("--???")
         ins("\n")
      end
      ins(indent(depth - 1))
      ins("end")
      return table.concat(out)
   else
      return info.str
   end
end

return lsp_formatter
