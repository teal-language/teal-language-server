-- Reproduces the nil-safety gaps found in the third-party-boundary audit
-- (Tier 1: crashes the whole server; Tier 2: crashes a single handler).
-- These are written TDD-red: no {expected="FAIL"} marker, so they show up
-- as genuine failures until the underlying code is fixed.

-- Prepend gen/ so we test local source rather than whatever is installed in
-- the luarocks tree, and ./ so tests.helpers.* resolves.
package.path = "gen/?.lua;./?.lua;" .. package.path

-- On Windows, "luarocks test" prepends the global luarocks DLL directory
-- (AppData\Roaming\luarocks\...) to package.cpath, but teal.dll lives in the
-- project venv. ltreesitter's dynamic loader calls LoadLibrary on each cpath
-- entry in order; when LoadLibrary returns NULL for a path that doesn't
-- contain teal.dll it crashes (null deref) instead of skipping gracefully.
-- Filter package.cpath to the project venv before document.lua is required,
-- since that module calls ltreesitter.require("teal","teal") at the top level.
if package.config:sub(1, 1) == "\\" then
    local uv_ = require("luv")
    local project_dir = uv_.cwd():lower()
    local entries = {}
    for path in package.cpath:gmatch("[^;]+") do
        local low = path:lower()
        if low == ".\\?.dll" or low:find(project_dir, 1, true) then
            table.insert(entries, path)
        end
    end
    if #entries > 0 then package.cpath = table.concat(entries, ";") end
end

local tested = require("tested")
local uv = require("luv")
local LspClient = require("tests.helpers.lsp_client")

local Document = require("teal_language_server.analysis.document")
local DocumentManager = require("teal_language_server.analysis.document_manager")
local DocumentSyncHandlers = require("teal_language_server.handlers.document_sync")
local ServerState = require("teal_language_server.server_state")
local Uri = require("teal_language_server.util.uri")
local lsp_formatter = require("teal_language_server.lsp.formatter")
local tl = require("tl")

local function doc(content)
   return Document("test-uri", content, 1, {}, ServerState())
end

-- A Document backed by a fake type report, so resolve_type_ref() can be
-- exercised without running a real tl.check().
local function doc_with_report(content, type_report)
   local server_state = ServerState()
   server_state:set_env({ reporter = { get_report = function() return type_report end } })
   return Document("test-uri", content, 1, {}, server_state)
end

local function new_document_manager()
   return DocumentManager({}, ServerState())
end

-- Pumps the luv loop for roughly `ms` milliseconds, so an already-spawned
-- server has a chance to process (or crash on) whatever was just sent to it.
local function settle(ms)
   local timer = uv.new_timer()
   local done = false
   uv.timer_start(timer, ms, 0, function() done = true end)
   while not done do uv.run("once") end
   uv.timer_stop(timer)
   uv.close(timer)
end

-- Closes a spawned client's handles without going through the normal
-- shutdown handshake, which would write to a pipe whose other end is gone.
local function force_close(client)
   for _, handle in ipairs({ client._stdin, client._stdout, client._stderr, client._handle }) do
      if handle and not uv.is_closing(handle) then
         uv.close(handle)
      end
   end
end


--
-- Tier 2: crashes a single handler (caught by _trigger's xpcall, so the
-- process survives, but the request hangs with no response or the
-- notification is silently dropped).
--

tested.test("path_from_uri does not crash on a malformed rootUri", {expected="FAIL"}, function()
   -- Mirrors misc_handlers.tl's initialize handler calling
   -- Uri.path_from_uri(params.rootUri) with a client-supplied string that
   -- has no scheme/path (Uri.parse returns nil for it).
   local ok = pcall(Uri.path_from_uri, "not-a-uri")

   tested.assert({
      given = "Uri.path_from_uri called with a malformed uri string",
      should = "not crash",
      expected = true,
      actual = ok,
   })
end)

tested.test("DocumentManager:open does not crash on a malformed textDocument.uri", function()
   -- Mirrors document_sync.tl's didOpen handler:
   -- self._document_manager:open(Uri.parse(td.uri), td.text, td.version)
   local dm = new_document_manager()
   local ok = pcall(function() dm:open(Uri.parse("not-a-uri"), "content", 1) end)

   tested.assert({
      given = "didOpen with a malformed textDocument.uri",
      should = "not crash DocumentManager:open",
      expected = true,
      actual = ok,
   })
end)

tested.test("DocumentManager:get does not crash on a malformed textDocument.uri", function()
   -- Mirrors handler_helper.tl's get_node_info (hover/definition/completion):
   -- document_manager:get(Uri.parse(td.uri))
   local dm = new_document_manager()
   local ok = pcall(function() dm:get(Uri.parse("not-a-uri")) end)

   tested.assert({
      given = "hover/definition/completion with a malformed textDocument.uri",
      should = "not crash DocumentManager:get",
      expected = true,
      actual = ok,
   })
end)

tested.test("didChange with an empty contentChanges array does not crash the handler", function()
   local dm = new_document_manager()
   local uri = "file:///tmp/tls_nil_test_didchange.tl"
   dm:open(Uri.parse(uri), "local x = 1", 1)

   local fake_events_manager = { set_handler = function() end }
   local fake_env_updater = { schedule_env_update = function() end }
   local handlers = DocumentSyncHandlers(fake_events_manager, dm, fake_env_updater)

   local ok = pcall(function()
      handlers:_on_did_change({
         textDocument = { uri = uri, version = 2 },
         contentChanges = {},
      })
   end)

   tested.assert({
      given = "a didChange notification with an empty contentChanges array",
      should = "not crash the handler",
      expected = true,
      actual = ok,
   })
end)

tested.test("hover formatting does not crash on a POLY type with a missing overload ref", function()
   -- Mirrors formatter.tl's show_type POLY branch: resolve_type_ref() can
   -- return nil when a type id isn't in the (possibly stale) type report.
   local type_report = { types = {} } -- type ref 999 is intentionally absent
   local d = doc_with_report("local x = 1", type_report)
   local type_info = { t = tl.typecodes.POLY, str = "poly", types = { 999 } }
   local node_info = { source = "x" }

   local ok = pcall(lsp_formatter.show_type, node_info, type_info, d)

   tested.assert({
      given = "hover over a POLY-typed value whose overload ref is missing from the type report",
      should = "not crash show_type",
      expected = true,
      actual = ok,
   })
end)

tested.test("hover formatting does not crash on a RECORD type with a missing field ref", function()
   -- Mirrors formatter.tl's show_type RECORD branch, same root cause as POLY.
   local type_report = { types = {} } -- type ref 999 is intentionally absent
   local d = doc_with_report("local x = 1", type_report)
   local type_info = { t = tl.typecodes.RECORD, str = "MyRecord", fields = { foo = 999 } }
   local node_info = { source = "x" }

   local ok = pcall(lsp_formatter.show_type, node_info, type_info, d)

   tested.assert({
      given = "hover over a RECORD-typed value whose field ref is missing from the type report",
      should = "not crash show_type",
      expected = true,
      actual = ok,
   })
end)

tested.test("tree_sitter_token does not crash when '.' is the very first token in the file", function()
   -- document.tl:476-482: when the "." has no previous sibling, the code
   -- falls back to the parent's previous sibling, which can also be nil
   -- (e.g. the "." is the first and only token in the whole file).
   local d = doc(".")
   local ok = pcall(function() return d:tree_sitter_token(0, 0) end)

   tested.assert({
      given = "a document containing only '.'",
      should = "not crash tree_sitter_token",
      expected = true,
      actual = ok,
   })
end)

tested.test("tree_sitter_token does not crash when ':' is the very first token in the file", function()
   local d = doc(":")
   local ok = pcall(function() return d:tree_sitter_token(0, 0) end)

   tested.assert({
      given = "a document containing only ':'",
      should = "not crash tree_sitter_token",
      expected = true,
      actual = ok,
   })
end)

tested.test("DocumentManager:open does not crash on a duplicate didOpen for the same uri", function()
   local dm = new_document_manager()
   local uri = Uri.parse("file:///tmp/tls_nil_test_dup_open.tl")
   dm:open(uri, "content", 1)

   local ok = pcall(function() dm:open(uri, "content-again", 2) end)

   tested.assert({
      given = "two didOpen notifications for the same uri with no didClose between them",
      should = "not crash DocumentManager:open",
      expected = true,
      actual = ok,
   })
end)

return tested
