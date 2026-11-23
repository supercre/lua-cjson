local cjson = require "cjson"
local safe = require "cjson.safe"
local count = 0

local function check(condition, message)
    count = count + 1
    assert(condition, message or "compat assertion failed")
end

local function fails(fn, pattern)
    local ok, err = pcall(fn)
    check(not ok and type(err) == "string" and err:match(pattern), tostring(err))
end

local function size(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- decode_lua_nil: off by default, per instance
check(cjson.decode_lua_nil() == false)
check(cjson.decode("null") == cjson.null)
check(cjson.decode('{"a":null}').a == cjson.null)
check(cjson.decode("[1,null,3]")[2] == cjson.null)
fails(function() cjson.decode_lua_nil("yes") end, "invalid option")
fails(function() cjson.decode_lua_nil(true, false) end, "too many arguments")
check(cjson.decode_lua_nil() == false)

check(cjson.decode_lua_nil(true) == true)
check(cjson.decode_lua_nil() == true)
check(select("#", cjson.decode("null")) == 1 and cjson.decode("null") == nil)
local object = cjson.decode('{"a":null,"b":1,"c":{"d":null,"e":[null]}}')
check(object.a == nil and object.b == 1 and size(object) == 2)
check(object.c.d == nil and size(object.c) == 1 and size(object.c.e) == 0)
local array = cjson.decode("[1,null,3]")
check(array[1] == 1 and array[2] == nil and array[3] == 3 and size(array) == 2)
check(size(cjson.decode("[null]")) == 0 and size(cjson.decode("[null,null]")) == 0)
check(cjson.encode(cjson.decode('{"a":null}')) == "{}")
check(cjson.encode(cjson.null) == "null" and cjson.encode({ a = cjson.null }) == '{"a":null}')
-- other values are untouched
check(cjson.decode("false") == false and cjson.decode("0") == 0 and cjson.decode('""') == "")
check(cjson.new().decode_lua_nil() == false and cjson.new().decode("null") == cjson.null)
check(safe.decode_lua_nil() == false and safe.decode("null") == cjson.null)
check(safe.new().decode_lua_nil(true) == true)
check(cjson.decode_lua_nil(false) == false and cjson.decode("null") == cjson.null)

-- decode_invalid_escapes: off by default, per instance
check(cjson.decode_invalid_escapes() == false)
for _, text in ipairs({ [["a\qb"]], [["a\'b"]], [["a\xb"]], [["\0"]], [["a\ b"]] }) do
    fails(function() cjson.decode(text) end, "invalid escape code")
end
fails(function() cjson.decode_invalid_escapes(1) end, "invalid option")
check(cjson.decode_invalid_escapes(true) == true)
check(cjson.decode([["a\qb"]]) == "aqb")
check(cjson.decode([["a\'b"]]) == "a'b")
check(cjson.decode([["a\xb"]]) == "axb")
check(cjson.decode([["a\ b"]]) == "a b")
check(cjson.decode([["\0"]]) == "0")
check(cjson.decode([[{"k\ey":"v\al"}]]).key == "val")
-- valid escapes keep their meaning
check(cjson.decode([["\n\t\"\\\/\b\f\r"]]) == "\n\t\"\\/\b\f\r")
check(cjson.decode([["\u0041\ud83d\ude00"]]) == "A\240\159\152\128")
-- still errors
fails(function() cjson.decode([["\u12"]]) end, "invalid unicode escape code")
fails(function() cjson.decode([["\uZZZZ"]]) end, "invalid unicode escape code")
fails(function() cjson.decode('"abc\\') end, "invalid escape code")
fails(function() cjson.decode('"abc') end, "unexpected end of string")
check(cjson.new().decode_invalid_escapes() == false)
check(safe.decode_invalid_escapes() == false)
local value, message = safe.decode([["a\qb"]])
check(value == nil and message:match("invalid escape code"))
check(cjson.decode_invalid_escapes(false) == false)
fails(function() cjson.decode([["a\qb"]]) end, "invalid escape code")

-- both together, as a host that needs the older cocos2d-x behaviour would set them
cjson.decode_lua_nil(true)
cjson.decode_invalid_escapes(true)
local mixed = cjson.decode([[{"name":"a\qb","gone":null,"list":[null,"\'"]}]])
check(mixed.name == "aqb" and mixed.gone == nil and mixed.list[2] == "'" and size(mixed.list) == 1)
cjson.decode_lua_nil(false)
cjson.decode_invalid_escapes(false)

print(("decode compatibility options: %d assertions passed"):format(count))
