#include <errno.h>
#include <lua.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// TODO: Windows

static int luapoll(lua_State *L) {
    struct pollfd fd = {
        .fd = fileno(stdin),
        .events = POLLIN,
        .revents = 0,
    };
    int result = poll(&fd, 1, 0);
    if (result < 0) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }
    if (fd.revents & POLLERR) {
        lua_pushnil(L);
        lua_pushstring(L, strerror(errno));
        return 2;
    }
    int data_available = fd.revents & POLLIN;
    lua_pushboolean(L, data_available);
    return 1;
}

LUA_API int luaopen_tealls_poll(lua_State *L) {
    lua_pushcfunction(L, luapoll);
    return 1;
}
