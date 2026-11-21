local cjson = require "cjson"
local safe = require "cjson.safe"
local count = 0

local function check(condition, message)
    count = count + 1
    assert(condition, message or "int64 assertion failed")
end

local function fails(fn, pattern)
    local ok, err = pcall(fn)
    check(not ok and type(err) == "string" and err:match(pattern), tostring(err))
end

check(cjson.decode_int64() == "off")
check(type(cjson.decode("9223372036854775807")) == "number")
check(type(cjson.decode("18446744073709551616")) == "number")
fails(function() cjson.decode_int64("invalid") end, "invalid option")
fails(function() cjson.decode_int64("auto", "always") end, "too many arguments")
check(cjson.decode_int64() == "off")

local has_ffi, ffi = pcall(require, "ffi")
if not has_ffi then
    fails(function() cjson.decode_int64("auto") end, "LuaJIT FFI is required")
    fails(function() cjson.decode_int64("always") end, "LuaJIT FFI is required")
    check(cjson.decode_int64() == "off")
    check(cjson.encode({ 1, 2, 3 }) == "[1,2,3]")
    print(("int64 compatibility: %d assertions passed (FFI unavailable)"):format(count))
    return
end

-- 큰 정수를 Lua number 리터럴로 만들면 테스트 입력부터 반올림된다.
local compile = loadstring or load
local function literal(text, suffix)
    return assert(compile("return " .. text .. suffix))()
end

local cases = {
    { "0", "LL" }, { "1", "LL" }, { "-1", "LL" },
    { "2147483647", "LL" }, { "2147483648", "LL" },
    { "4294967295", "LL" }, { "4294967296", "LL" },
    { "9007199254740990", "LL" }, { "9007199254740991", "LL" },
    { "9007199254740992", "LL" }, { "9007199254740993", "LL" },
    { "-9007199254740991", "LL" }, { "-9007199254740992", "LL" },
    { "-9007199254740993", "LL" },
    { "9223372036854775806", "LL" }, { "9223372036854775807", "LL" },
    { "-9223372036854775807", "LL" }, { "-9223372036854775808", "LL" },
    { "9223372036854775808", "ULL" },
    { "18446744073709551614", "ULL" }, { "18446744073709551615", "ULL" }
}

for _, keep_buffer in ipairs({ true, false }) do
    local json = cjson.new()
    json.encode_keep_buffer(keep_buffer)
    json.encode_number_precision(1)
    check(json.decode_int64("always") == "always")
    for _, case in ipairs(cases) do
        local text, suffix = case[1], case[2]
        local value = literal(text, suffix)
        check(json.encode(value) == text, text)
        local decoded = json.decode(text)
        check(type(decoded) == "cdata", text)
        check(tostring(decoded) == text .. suffix, text)
        check(json.encode(decoded) == text, text)
        check(json.encode({ value, { id = value } }) ==
              "[" .. text .. ",{\"id\":" .. text .. "}]", text)
        check(json.encode({ [value] = "value" }) ==
              "{\"" .. text .. "\":\"value\"}", text)
        local nested = json.decode("[{\"id\":" .. text .. "}]")
        check(tostring(nested[1].id) == text .. suffix, text)
    end
    check(json.encode(ffi.new("uint64_t", 42)) == "42")
    check(json.encode(ffi.new("const int64_t", -42)) == "-42")
    check(json.decode("-0") == ffi.new("int64_t", 0))
    check(type(json.decode("1.0")) == "number")
    check(type(json.decode("1e3")) == "number")
    check(type(json.decode("18446744073709551616.0")) == "number")
    check(type(json.decode("18446744073709551616e0")) == "number")

    local pretending = ffi.metatype("struct { int unused; }", {
        __tostring = function() return "42LL" end
    })
    local unsupported = {
        ffi.new("int32_t", 42), ffi.new("double", 42),
        ffi.new("int64_t[1]", 42), ffi.cast("int64_t *", 0),
        ffi.typeof("int64_t"), pretending()
    }
    for _, value in ipairs(unsupported) do
        fails(function() json.encode(value) end, "only int64_t and uint64_t")
        fails(function() json.encode({ [value] = 1 }) end, "only int64_t and uint64_t")
        check(json.encode(literal("9223372036854775807", "LL")) == "9223372036854775807")
    end
end

local auto = cjson.new()
check(auto.decode_int64("auto") == "auto")
for _, text in ipairs({ "0", "42", "-42", "9007199254740991", "-9007199254740991" }) do
    check(type(auto.decode(text)) == "number", text)
end
for _, text in ipairs({ "9007199254740992", "9007199254740993",
                        "-9007199254740992", "-9007199254740993",
                        "9223372036854775807", "-9223372036854775808" }) do
    check(tostring(auto.decode(text)) == text .. "LL", text)
end
check(tostring(auto.decode("18446744073709551615")) == "18446744073709551615ULL")
check(type(auto.decode("0x10")) == "number")
check(type(auto.decode("1.5")) == "number")
check(type(auto.decode("1e20")) == "number")
check(1 / auto.decode("-0") == -math.huge)

for _, mode in ipairs({ "auto", "always" }) do
    local json = safe.new()
    json.decode_int64(mode)
    for _, text in ipairs({ "18446744073709551616", "-9223372036854775809",
                            "999999999999999999999999999999999999999" }) do
        for _, input in ipairs({ text, "[" .. text .. "]", "{\"id\":" .. text .. "}" }) do
            local value, err = json.decode(input)
            check(value == nil and err:match("integer outside int64/uint64 range"), input)
        end
    end
    local value, err = json.encode(ffi.new("double", 1))
    check(value == nil and err:match("only int64_t and uint64_t"))
    check(json.encode(json.decode("9223372036854775807")) == "9223372036854775807")
    json.decode_invalid_numbers(false)
    for _, text in ipairs({ "+42", "01", "0x10", "NaN", "Infinity",
                            "9223372036854775807x", "[9223372036854775807,]" }) do
        check(json.decode(text) == nil, text)
    end
    check(json.decode_int64("off") == "off")
    check(type(json.decode("18446744073709551616")) == "number")
end

-- new()와 safe 모듈의 설정 및 GC 수명은 서로 독립적이어야 한다.
check(cjson.decode_int64() == "off")
check(safe.decode_int64() == "off")
check(auto.new().decode_int64() == "off")
local encode = cjson.new().encode
local instance = cjson.new()
instance.decode_int64("always")
local decode = instance.decode
instance = nil
collectgarbage("collect")
check(encode(decode("9223372036854775807")) == "9223372036854775807")

local deep = string.rep("[", 1000) .. "9223372036854775807" .. string.rep("]", 1000)
check(encode(decode(deep)) == deep)

-- 부호와 상/하위 32비트가 다양한 값을 JIT 활성/비활성 상태에서 왕복한다.
local state = 17
local function next32()
    state = (state * 1664525 + 1013904223) % 4294967296
    return state
end
local unsigned = ffi.typeof("uint64_t")
local two32 = unsigned(4294967296)
for i = 1, 5000 do
    local value = unsigned(next32()) * two32 + unsigned(next32())
    if i % 2 == 0 then value = ffi.cast("int64_t", value) end
    local text = tostring(value):gsub("U?LL$", "")
    check(encode(value) == text)
    check(encode(decode(text)) == text)
end

print(("LuaJIT int64: %d assertions passed"):format(count))
