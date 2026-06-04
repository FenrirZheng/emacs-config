# junit-core -- Emacs dynamic module: JUnit test discovery for Java files.
#
# Built as part of the cpp/ workspace (see ../CMakeLists.txt); the toolchain
# defaults (C++17, PIC, output -> cpp/lib/) are inherited from the parent.
# Can also be configured standalone:
#
#   cmake -S . -B build && cmake --build build

cmake_minimum_required(VERSION 3.16)
project(junit_core LANGUAGES C CXX)

# Standalone-build fallback: if configured directly (not via the parent
# aggregator), still emit the .so into the workspace-wide cpp/lib/.
if(NOT DEFINED CMAKE_LIBRARY_OUTPUT_DIRECTORY)
  set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../lib)
endif()

# --- tree-sitter runtime (libtree-sitter-dev) -------------------------------
# Provides <tree_sitter/api.h> and libtree-sitter.  Try pkg-config first, then
# a plain library/header search.
find_package(PkgConfig QUIET)
if(PkgConfig_FOUND)
  pkg_check_modules(TREE_SITTER QUIET tree-sitter)
endif()

find_library(TS_LIBRARY NAMES tree-sitter HINTS ${TREE_SITTER_LIBRARY_DIRS})
find_path(TS_INCLUDE_DIR tree_sitter/api.h HINTS ${TREE_SITTER_INCLUDE_DIRS})

if(NOT TS_LIBRARY OR NOT TS_INCLUDE_DIR)
  message(FATAL_ERROR
    "libtree-sitter runtime not found.\n"
    "Install it with:  sudo apt install libtree-sitter-dev")
endif()

# --- the module -------------------------------------------------------------
# emacs-module.h lives in a default include path (/usr/include) on this system.
add_library(junit-core MODULE
  src/junit-core.cpp
  vendor/tree-sitter-java/parser.c)

# Emacs loads `FEATURE.so'; drop the lib prefix and force the .so suffix.
set_target_properties(junit-core PROPERTIES
  PREFIX ""
  OUTPUT_NAME "junit-core"
  SUFFIX ".so")

target_include_directories(junit-core PRIVATE
  ${TS_INCLUDE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/vendor/tree-sitter-java)  # for tree_sitter/parser.h

target_link_libraries(junit-core PRIVATE ${TS_LIBRARY})

# The grammar's parser.c is plain C; keep it from inheriting C++ flags.
set_source_files_properties(vendor/tree-sitter-java/parser.c PROPERTIES LANGUAGE C)
