#include "lua.h"

/* Windows DLL export stub required by LuaRocks builtin build type.
   ltreesitter loads this library via dlopen/LoadLibrary and calls
   tree_sitter_teal() directly — luaopen_teal is never used at runtime. */
int luaopen_teal(lua_State *L) {
    (void)L;
    return 0;
}
