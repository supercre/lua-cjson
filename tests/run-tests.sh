#!/bin/sh
set -eu

LUA_COMMAND=${1:-luajit}
SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
MODULE_DIR=$(CDPATH= cd -- "${2:-$SOURCE_DIR}" && pwd)

export LUA_PATH="$SOURCE_DIR/lua/?.lua;;"
export LUA_CPATH="$MODULE_DIR/?.so;$MODULE_DIR/?.dll;;"

cd "$SOURCE_DIR/tests"
perl genutf8.pl
"$LUA_COMMAND" test.lua
"$LUA_COMMAND" test-int64.lua
"$LUA_COMMAND" test-compat.lua
if "$LUA_COMMAND" -e 'assert(jit)' 2>/dev/null; then
    "$LUA_COMMAND" -joff test-int64.lua
    "$LUA_COMMAND" -joff test-compat.lua
fi
