cmake_minimum_required(VERSION 3.14)
project(quickjs_native LANGUAGES C)

include(CheckIPOSupported)

set(QUICKJS_ROOT "${CMAKE_CURRENT_LIST_DIR}/../third_party/quickjs")

if(NOT EXISTS "${QUICKJS_ROOT}/CMakeLists.txt")
  message(FATAL_ERROR
    "QuickJS sources not found at ${QUICKJS_ROOT}. "
    "The package is incomplete; third_party/quickjs must be included in the "
    "published plugin archive.")
endif()

set(QJS_ENABLE_INSTALL OFF CACHE BOOL "" FORCE)
set(QJS_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(QJS_BUILD_WERROR OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_subdirectory("${QUICKJS_ROOT}" "${CMAKE_BINARY_DIR}/quickjs" EXCLUDE_FROM_ALL)

# QuickJS is built as static libraries and then linked into the plugin's
# shared library. Ensure every object is suitable for shared-library linkage,
# including Linux release builds where IPO/LTO exposes non-PIC relocations.
set_target_properties(qjs qjs-libc PROPERTIES
  POSITION_INDEPENDENT_CODE ON
)

add_library(quickjs SHARED
  quickjs_bridge.c
)

if(CMAKE_SYSTEM_NAME STREQUAL "OHOS")
  # HarmonyOS' hmos.toolchain.cmake cannot configure the nested project used
  # by CheckIPOSupported because its OHOS_SDK_NATIVE value is not propagated.
  # Keep the normal release optimization and skip only cross-target IPO/LTO.
  set(LEMON_JS_IPO_SUPPORTED FALSE)
  set(LEMON_JS_IPO_ERROR "disabled for the HarmonyOS cross toolchain")
else()
  check_ipo_supported(
    RESULT LEMON_JS_IPO_SUPPORTED
    OUTPUT LEMON_JS_IPO_ERROR
    LANGUAGES C
  )
endif()

if(LEMON_JS_IPO_SUPPORTED)
  foreach(target qjs qjs-libc quickjs)
    set_property(
      TARGET ${target}
      PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE
    )
    set_property(
      TARGET ${target}
      PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELWITHDEBINFO TRUE
    )
    set_property(
      TARGET ${target}
      PROPERTY INTERPROCEDURAL_OPTIMIZATION_MINSIZEREL TRUE
    )
  endforeach()
else()
  message(STATUS "Release IPO/LTO unavailable: ${LEMON_JS_IPO_ERROR}")
endif()

set_target_properties(quickjs PROPERTIES
  OUTPUT_NAME "quickjs"
  C_VISIBILITY_PRESET default
)

target_include_directories(quickjs PRIVATE "${QUICKJS_ROOT}")
target_compile_definitions(quickjs PRIVATE QUICKJS_BRIDGE_BUILD)
target_link_libraries(quickjs PRIVATE qjs qjs-libc)

if(ANDROID)
  find_library(log-lib log)
  target_link_libraries(quickjs PRIVATE ${log-lib})
  target_link_options(quickjs PRIVATE "-Wl,-z,max-page-size=16384")
endif()

if(APPLE)
  find_library(core_foundation_lib CoreFoundation)
  if(core_foundation_lib)
    target_link_libraries(quickjs PRIVATE ${core_foundation_lib})
  endif()
endif()
