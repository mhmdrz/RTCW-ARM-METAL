cmake_minimum_required(VERSION 3.20)
project(RTCW_SP C CXX)

#
# Return to Castle Wolfenstein (Single Player) - modern arm64 build.
#
#   macOS (arm64): engine executable + 3 dynamically loaded module dylibs
#                  (qagame/cgame/ui), rendering via OpenGL, platform via SDL2.
#   iOS/iPadOS   : scaffolded below (hard-linked modules). NOTE: iOS has no
#                  desktop OpenGL, so the iOS target cannot LINK until the
#                  Metal renderer (Part 6) exists. It is intentionally gated.
#

set(CMAKE_C_STANDARD 99)
set(CMAKE_CXX_STANDARD 14)

# Renderer backend: OpenGL (default, macOS) or Metal (required for iOS).
option(USE_METAL "Use the Metal renderer backend instead of OpenGL" OFF)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

set(SRC ${CMAKE_SOURCE_DIR}/src)

# Detect Apple platform
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  set(RTCW_IOS TRUE)
  set(USE_METAL ON CACHE BOOL "iOS requires Metal" FORCE)   # no OpenGL on iOS
else()
  set(RTCW_IOS FALSE)
endif()

if(USE_METAL)
  add_compile_definitions(USE_METAL)
  message(STATUS "Renderer backend: Metal")
else()
  message(STATUS "Renderer backend: OpenGL")
endif()

if(NOT RTCW_IOS AND NOT CMAKE_OSX_ARCHITECTURES)
  set(CMAKE_OSX_ARCHITECTURES "arm64")
endif()

# ----------------------------------------------------------------------------
# Common include directories (every target needs the shared headers)
# ----------------------------------------------------------------------------
set(RTCW_INCLUDES
  ${SRC}/qcommon ${SRC}/game ${SRC}/renderer ${SRC}/cgame
  ${SRC}/client ${SRC}/server ${SRC}/botlib ${SRC}/splines ${SRC}/botai ${SRC}/ui)

# Silence the macOS OpenGL-deprecation noise; the renderer is fixed-function GL.
add_compile_definitions(GL_SILENCE_DEPRECATION)

# RTCW uses gnu89 inline semantics (bare __inline emits an out-of-line copy).
# Modern clang defaults to C99 inline, which would drop those bodies and
# produce undefined references (e.g. Matrix4MultiplyInto3x3AndTranslation).
add_compile_options($<$<COMPILE_LANGUAGE:C>:-fgnu89-inline>)

# ----------------------------------------------------------------------------
# SDL2
# ----------------------------------------------------------------------------
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
  pkg_check_modules(SDL2 sdl2)
endif()
if(NOT SDL2_FOUND)
  # Homebrew fallback
  set(SDL2_INCLUDE_DIRS /opt/homebrew/opt/sdl2/include/SDL2)
  set(SDL2_LIBRARY_DIRS /opt/homebrew/opt/sdl2/lib)
  set(SDL2_LIBRARIES SDL2)
endif()

# ----------------------------------------------------------------------------
# Static support libraries (linked into the engine)
# ----------------------------------------------------------------------------
file(GLOB BOTLIB_SRC ${SRC}/botlib/*.c)
add_library(rtcw_botlib STATIC ${BOTLIB_SRC})
target_include_directories(rtcw_botlib PRIVATE ${RTCW_INCLUDES})
target_compile_definitions(rtcw_botlib PRIVATE BOTLIB)

file(GLOB JPEG_SRC ${SRC}/jpeg-6/*.c)
add_library(rtcw_jpeg STATIC ${JPEG_SRC})
target_include_directories(rtcw_jpeg PRIVATE ${SRC}/jpeg-6)

file(GLOB SPLINES_SRC ${SRC}/splines/*.cpp)
add_library(rtcw_splines STATIC ${SPLINES_SRC})
target_include_directories(rtcw_splines PRIVATE ${RTCW_INCLUDES})

# ----------------------------------------------------------------------------
# Engine executable source list
# ----------------------------------------------------------------------------
file(GLOB RENDERER_SRC ${SRC}/renderer/*.c)
file(GLOB CLIENT_SRC   ${SRC}/client/*.c)   # cl_*.c + snd_*.c
file(GLOB SERVER_SRC   ${SRC}/server/*.c)
file(GLOB QCOMMON_SRC  ${SRC}/qcommon/*.c)
list(REMOVE_ITEM QCOMMON_SRC ${SRC}/qcommon/vm_x86.c)   # x86 JIT - not on arm64
# use the no-JIT stub (VM_Compile / VM_CallCompiled) in its place
list(APPEND QCOMMON_SRC ${SRC}/unix/vm_x86.c)

set(PLATFORM_SRC
  ${SRC}/unix/unix_main.c
  ${SRC}/unix/unix_net.c
  ${SRC}/unix/unix_shared.c
  ${SRC}/sdl/sdl_input.c
  ${SRC}/sdl/sdl_snd.c)

if(USE_METAL)
  # Metal backend: the GL-on-Metal shim + Metal windowing replace sdl_glimp.c.
  # -fno-operator-names: tr_local.h uses `or` as an identifier, which is a C++
  # alternative-operator keyword in these ObjC++ sources.
  set_source_files_properties(${SRC}/metal/mtl_gl.mm ${SRC}/metal/mtl_glimp.mm
    PROPERTIES COMPILE_OPTIONS "-fno-operator-names")
  list(APPEND PLATFORM_SRC ${SRC}/metal/mtl_gl.mm ${SRC}/metal/mtl_glimp.mm)
else()
  list(APPEND PLATFORM_SRC ${SRC}/sdl/sdl_glimp.c)
endif()

set(ENGINE_SRC
  ${SRC}/game/q_shared.c
  ${SRC}/game/q_math.c
  ${RENDERER_SRC}
  ${CLIENT_SRC}
  ${SERVER_SRC}
  ${QCOMMON_SRC}
  ${PLATFORM_SRC})

add_executable(wolfsp ${ENGINE_SRC})
target_include_directories(wolfsp PRIVATE ${RTCW_INCLUDES} ${SDL2_INCLUDE_DIRS})
target_link_directories(wolfsp PRIVATE ${SDL2_LIBRARY_DIRS})
target_link_libraries(wolfsp PRIVATE rtcw_botlib rtcw_jpeg rtcw_splines ${SDL2_LIBRARIES} m)

if(NOT RTCW_IOS)
  target_link_libraries(wolfsp PRIVATE
    "-framework Cocoa" "-framework IOKit"
    "-framework CoreAudio" "-framework AudioToolbox" "-framework CoreVideo"
    "-framework Carbon" "-framework ForceFeedback" "-framework CoreFoundation"
    dl)
  if(USE_METAL)
    target_link_libraries(wolfsp PRIVATE
      "-framework Metal" "-framework QuartzCore" "-framework Foundation")
  else()
    target_link_libraries(wolfsp PRIVATE "-framework OpenGL")
  endif()
endif()

# ----------------------------------------------------------------------------
# Loadable game modules (macOS: separate .dylib loaded via Sys_LoadDll)
# ----------------------------------------------------------------------------
function(rtcw_module name)
  add_library(${name} MODULE ${ARGN})
  target_include_directories(${name} PRIVATE ${RTCW_INCLUDES})
  set_target_properties(${name} PROPERTIES PREFIX "" SUFFIX ".dylib")
  # modules are self-contained; allow any stray host symbol to resolve at load
  target_link_options(${name} PRIVATE "-undefined" "dynamic_lookup")
endfunction()

# game (qagame.dylib)
file(GLOB GAME_SRC  ${SRC}/game/*.c)
list(REMOVE_ITEM GAME_SRC ${SRC}/game/bg_lib.c)   # QVM-only libc shim
file(GLOB BOTAI_SRC ${SRC}/botai/*.c)
rtcw_module(qagame ${GAME_SRC} ${BOTAI_SRC})
target_compile_definitions(qagame PRIVATE GAMEDLL)

# cgame (cgame.dylib)
file(GLOB CGAME_SRC ${SRC}/cgame/*.c)
rtcw_module(cgame
  ${CGAME_SRC}
  ${SRC}/game/bg_animation.c ${SRC}/game/bg_misc.c
  ${SRC}/game/bg_pmove.c ${SRC}/game/bg_slidemove.c
  ${SRC}/game/q_math.c ${SRC}/game/q_shared.c
  ${SRC}/ui/ui_shared.c)
target_compile_definitions(cgame PRIVATE CGAMEDLL)

# ui (ui.dylib)
file(GLOB UI_SRC ${SRC}/ui/*.c)
rtcw_module(ui
  ${UI_SRC}
  ${SRC}/game/bg_misc.c
  ${SRC}/game/q_math.c ${SRC}/game/q_shared.c)

# ----------------------------------------------------------------------------
# iOS scaffold (hard-linked, Metal - gated; cannot link until Part 6)
# ----------------------------------------------------------------------------
if(RTCW_IOS)
  # iOS hard-links the game modules into the engine and renders via Metal.
  target_compile_definitions(wolfsp PRIVATE RTCW_HARD_LINKED)
  target_sources(wolfsp PRIVATE ${GAME_SRC} ${BOTAI_SRC} ${CGAME_SRC} ${UI_SRC})
  target_link_libraries(wolfsp PRIVATE
    "-framework UIKit" "-framework Metal" "-framework QuartzCore"
    "-framework Foundation" "-framework AudioToolbox")
  # NOTE: a full iOS link/run additionally needs the SDL2 iOS static library
  # and an app bundle (Info.plist, launch storyboard) + bundled assets. The
  # renderer/translation layer itself is iOS-ready (Metal).
endif()
