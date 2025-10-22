local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local _module_name = "diagnostics_helper"

local class = require("teal_language_server.class")
local lsp = require("teal_language_server.lsp")
local ServerState = require("teal_language_server.server_state")
local ModuleInfo = require("teal_language_server.module_info")
local tl = require("tl")
local util = require("teal_language_server.util")
local tracing = require("teal_language_server.tracing")

local DiagnosticsHelper = {}







function DiagnosticsHelper:__init(server_state)
   self._server_state = server_state
end


local function filter(t, pred)
   local pass = {}
   local fail = {}
   for _, v in ipairs(t) do
      table.insert(pred(v) and pass or fail, v)
   end
   return pass, fail
end

local function is_lua(fname)
   return fname:sub(-4) == ".lua"
end


local function make_diagnostic_from_error(tks, err, severity)
   local x, y = err.x, err.y
   local err_tk = tl.get_token_at(tks, y, x)
   return {
      range = {
         start = {
            line = y - 1,
            character = x - 1,
         },
         ["end"] = {
            line = y - 1,
            character = (err_tk and x + #err_tk - 1) or x,
         },
      },
      severity = lsp.severity[severity],
      message = err.msg,
   }
end

local function insert_errs(fname, diags, tks, errs, sev)
   for _, err in ipairs(errs or {}) do
      if fname == err.filename then
         table.insert(diags, make_diagnostic_from_error(tks, err, sev))
      end
   end
end

local function imap(t, fn, start, finish)
   local new = {}
   for i = start or 1, finish or #t do
      new[i] = fn(t[i])
   end
   return new
end

function DiagnosticsHelper:create_diagnostics(module_info)
   local tks = module_info.tokens
   local err_tks = module_info.err_tokens

   if #err_tks > 0 then
      tracing.trace(_module_name, "Found {} error tokens for module {}", { #err_tks, module_info.module_name })
      return imap(err_tks, function(t)
         return {
            range = {
               start = lsp.position(t.y - 1, t.x - 1),
               ["end"] = lsp.position(t.y - 1, t.x - 1),
            },
            severity = lsp.severity.Error,
            message = "Unexpected token",
         }
      end)
   end

   local parse_errs = module_info.parse_errors

   if #parse_errs > 0 then
      tracing.trace(_module_name, "Found {} parse errors for module {}", { #parse_errs, module_info.module_name })
      return imap(parse_errs, function(e)
         return make_diagnostic_from_error(tks, e, "Error")
      end)
   end

   local diags = {}
   local fname = module_info.uri and module_info.uri.path or module_info.path
   local result = module_info.check_result

   if result == nil then
      tracing.warning(_module_name, "No check_result for module {}", { module_info.path })
      return diags
   end

   local config = self._server_state.config
   local disabled_warnings = util.set(config.disable_warnings or {})
   local warning_errors = util.set(config.warning_error or {})
   local enabled_warnings = filter(result.warnings, function(e)
      if is_lua(fname) then
         return not (disabled_warnings[e.tag] or
         e.msg:find("unknown variable"))
      else
         return not disabled_warnings[e.tag]
      end
      return
   end)
   local werrors, warnings = filter(enabled_warnings, function(e)
      return warning_errors[e.tag]
   end)
   insert_errs(fname, diags, tks, warnings, "Warning")
   insert_errs(fname, diags, tks, werrors, "Error")
   insert_errs(fname, diags, tks, result.type_errors, "Error")

   tracing.trace(_module_name, "Found {} diagnostics for module {}", { #diags, module_info.module_name })
   return diags
end

class.setup(DiagnosticsHelper, "DiagnosticsHelper", {})


return DiagnosticsHelper
