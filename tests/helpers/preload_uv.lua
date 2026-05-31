-- tested language-handler that does nothing except pre-load luv and cjson
-- before any test file runs. Without this, tested's per-file
-- `package.loaded[...] = nil` + collectgarbage cycle re-initializes libuv
-- between test files, which corrupts the event loop and segfaults after a few
-- iterations when running with `-n 0`.

local IS_WINDOWS = package.config:sub(1, 1) == "\\"

-- On Windows, luarocks prepends global install paths (e.g. AppData\Roaming\luarocks)
-- to package.cpath. These non-existent paths cause ltreesitter's dynamic DLL
-- loader to segfault when document_tree_sitter_test.lua loads document.lua directly
-- in the test process. Keep only paths within this project directory and the
-- current-directory wildcard.
local function filter_cpath_for_windows()
    if not IS_WINDOWS then return end
    local uv = require("luv")
    local project_dir = uv.cwd():lower()
    local entries = {}
    for path in package.cpath:gmatch("[^;]+") do
        local low = path:lower()
        if low == ".\\?.dll" or low:find(project_dir, 1, true) then
            table.insert(entries, path)
        end
    end
    if #entries > 0 then
        package.cpath = table.concat(entries, ";")
    end
end

return {
    extension = ".__preload_uv_dummy__",
    loader = function()
        return function() end
    end,
    setup = function()
        filter_cpath_for_windows()
        require("luv")
        require("cjson")
    end,
}
