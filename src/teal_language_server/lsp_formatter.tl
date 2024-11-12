local tl <const> = require("tl")

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
    local output = {}
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

local function indent(n: integer): string
   return ("   "):rep(n)
end
local function ti(list: {string}, ...: string)
   for i = 1, select("#", ...) do
      table.insert(list, (select(i, ...)))
   end
end

-- TODO: eventually get rid of tr here if possible
function lsp_formatter.show_type(info: tl.TypeInfo, tr: tl.TypeReport, depth?: integer): string
   if not info then return "???" end
   depth = depth or 1
   if depth > 4 then
      return "..."
   end

   local out <const>: {string} = {}

   local function ins(...: string)
      ti(out, ...)
   end

   local function show_record_field(name: string, field_id: integer): string
      local field <const> = {}
      ti(field, indent(depth))
      local field_type <const> = tr.types[field_id]
      if field_type.str:match("^type ") then
         ti(field, "type ", name, " = ", (lsp_formatter.show_type(field_type, tr, depth + 1):gsub("^type ", "")))
      else
         ti(field, name, ": ", lsp_formatter.show_type(field_type, tr, depth + 1))
      end
      ti(field, "\n")
      return table.concat(field)
   end

   local function show_record_fields(fields: {string:integer})
      if not fields then
         ins("--???\n")
         return
      end
      local f <const> = {}
      for name, field_id in pairs(fields) do
         ti(f, show_record_field(name, field_id))
      end
      local function get_name(s: string): string
         return (s:match("^%s*type ([^=]+)") or s:match("^%s*([^:]+)")):lower()
      end
      table.sort(f, function(a: string, b: string): boolean
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
   elseif info.t == tl.typecodes.ENUM then -- an enum def
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
