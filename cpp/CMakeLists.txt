# Top-level build for the cpp/ C++ libraries workspace.
#
# This is an aggregator: each Emacs dynamic module lives in its own
# subdirectory with its own CMakeLists.txt, and is pulled in via
# add_subdirectory below.  Every module's built `.so' is emitted into
# cpp/lib/, where the elisp loaders look for it.
#
#   cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
#   cmake --build build            # -> cpp/lib/<module>.so
#
# Prefer ./build.sh, which wraps the two commands above.  To add a new
# library, create cpp/<name>/CMakeLists.txt defining a MODULE target and add
# one `add_subdirectory(<name>)' line here.

cmake_minimum_required(VERSION 3.16)
project(emacs_cpp_libs LANGUAGES C CXX)

# Shared toolchain defaults inherited by every subproject.
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

# Collect every module's .so into cpp/lib/ regardless of where it is built.
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/lib)

# --- modules ----------------------------------------------------------------
add_subdirectory(junit-core)
