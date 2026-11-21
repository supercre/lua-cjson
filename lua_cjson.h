/* Lua CJSON 공개 진입점. MIT 라이선스는 LICENSE를 참고한다. */
#ifndef LUA_CJSON_H
#define LUA_CJSON_H

#ifdef __cplusplus
extern "C" {
#endif

struct lua_State;
int luaopen_cjson(struct lua_State *l);
int luaopen_cjson_safe(struct lua_State *l);

#ifdef __cplusplus
}
#endif

#endif
