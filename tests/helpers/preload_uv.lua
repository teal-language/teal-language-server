-- tested language-handler that does nothing except pre-load luv and cjson
-- before any test file runs. Without this, tested's per-file
-- `package.loaded[...] = nil` + collectgarbage cycle re-initializes libuv
-- between test files, which corrupts the event loop and segfaults after a few
-- iterations when running with `-n 0`.

return {
    extension = ".__preload_uv_dummy__",
    loader = function()
        return function() end
    end,
    setup = function()
        require("luv")
        require("cjson")
    end,
}
