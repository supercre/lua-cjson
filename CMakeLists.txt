# If Lua is installed in a non-standard location, please set the LUA_DIR
# environment variable to point to prefix for the install. Eg:
#       Unix: export LUA_DIR=/home/user/pkg
#       Windows: set LUA_DIR=c:\lua51

cmake_minimum_required(VERSION 3.10...4.0)
project(lua-cjson C)

option(USE_INTERNAL_FPCONV "Use internal strtod() / g_fmt() code for performance")
option(MULTIPLE_THREADS "Support multi-threaded apps with internal fpconv - recommended" ON)
option(CJSON_BUILD_STATIC "Build a static library for an existing Lua 5.1/LuaJIT runtime" OFF)

if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release CACHE STRING
        "Choose the type of build, options are: None Debug Release RelWithDebInfo MinSizeRel."
        FORCE)
endif()

if(CJSON_BUILD_STATIC)
    # 정적 라이브러리는 헤더만 사용하고 Lua 런타임은 소비자가 연결한다.
    find_path(LUA_INCLUDE_DIR lua.h PATH_SUFFIXES luajit-2.1 lua5.1)
    if(NOT LUA_INCLUDE_DIR)
        message(FATAL_ERROR "Set LUA_INCLUDE_DIR to Lua 5.1 or LuaJIT headers")
    endif()
else()
    find_package(Lua51 REQUIRED)
endif()
include_directories(${LUA_INCLUDE_DIR})

if(NOT USE_INTERNAL_FPCONV)
    # Use libc number conversion routines (strtod(), sprintf())
    set(FPCONV_SOURCES fpconv.c)
else()
    # Use internal number conversion routines
    add_definitions(-DUSE_INTERNAL_FPCONV)
    set(FPCONV_SOURCES g_fmt.c dtoa.c)

    include(TestBigEndian)
    TEST_BIG_ENDIAN(IEEE_BIG_ENDIAN)
    if(IEEE_BIG_ENDIAN)
        add_definitions(-DIEEE_BIG_ENDIAN)
    endif()

    if(MULTIPLE_THREADS)
        set(CMAKE_THREAD_PREFER_PTHREAD TRUE)
        find_package(Threads REQUIRED)
        if(NOT CMAKE_USE_PTHREADS_INIT)
            message(FATAL_ERROR
                    "Pthreads not found - required by MULTIPLE_THREADS option")
        endif()
        add_definitions(-DMULTIPLE_THREADS)
    endif()
endif()

# Handle platforms missing isinf() macro (Eg, some Solaris systems).
include(CheckSymbolExists)
CHECK_SYMBOL_EXISTS(isinf math.h HAVE_ISINF)
if(NOT HAVE_ISINF)
    add_definitions(-DUSE_INTERNAL_ISINF)
endif()

# Windows의 예전 C 런타임(msvcrt: VS2013 이하, MinGW)인지. VS2015부터의 UCRT는 C99를 따른다.
set(_cjson_windows_legacy_crt OFF)
if(WIN32 AND (NOT MSVC OR MSVC_VERSION LESS 1900))
    set(_cjson_windows_legacy_crt ON)
endif()

if(MSVC)
    add_definitions(-D_CRT_SECURE_NO_WARNINGS)
    add_definitions(-Dinline=__inline)
    # UCRT에서 snprintf는 표준 함수이고, 매크로로 정의하면 <stdio.h>가 오류를 낸다.
    if(_cjson_windows_legacy_crt)
        add_definitions(-Dsnprintf=_snprintf)
    endif()
    add_definitions(-Dstrncasecmp=_strnicmp)
endif()

set(_MODULE_LINK "${CMAKE_THREAD_LIBS_INIT}")
if(CJSON_BUILD_STATIC)
    add_library(cjson STATIC lua_cjson.c strbuf.c ${FPCONV_SOURCES})
    target_compile_definitions(cjson PRIVATE CJSON_STATIC)
    set_target_properties(cjson PROPERTIES OUTPUT_NAME "lua-cjson")
    target_link_libraries(cjson ${_MODULE_LINK})
    # 예전 C 런타임의 strtod()/sprintf()는 NaN/Infinity와 16진수를 표준대로 다루지 않아 지원하지 않는다.
    # UCRT에서는 다른 플랫폼과 같게 허용한다(막으면 Windows에서만 "01", "0x10", "NaN"의 디코딩이 오류가 된다).
    if(_cjson_windows_legacy_crt AND NOT USE_INTERNAL_FPCONV)
        target_compile_definitions(cjson PRIVATE DISABLE_INVALID_NUMBERS)
    endif()
    install(TARGETS cjson ARCHIVE DESTINATION lib)
    install(FILES lua_cjson.h DESTINATION include)
    return()
endif()

get_filename_component(_lua_lib_dir ${LUA_LIBRARY} PATH)

if(APPLE)
    set(CMAKE_SHARED_MODULE_CREATE_C_FLAGS
        "${CMAKE_SHARED_MODULE_CREATE_C_FLAGS} -undefined dynamic_lookup")
endif()

if(WIN32)
    # Win32 modules need to be linked to the Lua library.
    set(_MODULE_LINK ${LUA_LIBRARY} ${_MODULE_LINK})
    set(_lua_module_dir "${_lua_lib_dir}")
    # The old Windows C runtime's sprintf()/strtod() handle NaN/inf differently. Not supported there.
    if(_cjson_windows_legacy_crt)
        add_definitions(-DDISABLE_INVALID_NUMBERS)
    endif()
else()
    set(_lua_module_dir "${_lua_lib_dir}/lua/5.1")
endif()

add_library(cjson MODULE lua_cjson.c strbuf.c ${FPCONV_SOURCES})
set_target_properties(cjson PROPERTIES PREFIX "")
target_link_libraries(cjson ${_MODULE_LINK})
install(TARGETS cjson DESTINATION "${_lua_module_dir}")

# vi:ai et sw=4 ts=4:
