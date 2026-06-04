#!/usr/bin/env bash
# Build every C++ library in the cpp/ workspace.  Each module's .so lands in
# cpp/lib/, where the elisp loaders look for it.
#
#   cpp/build.sh            # configure + build all modules (Release)
#   cpp/build.sh clean      # remove build/ and lib/ first
#
# Requires: cmake and a C++17 compiler.  Individual modules declare their own
# dependencies in their CMakeLists.txt and fail configuration with an
# actionable message if one is missing (e.g. junit-core needs
# libtree-sitter-dev: sudo apt install libtree-sitter-dev).
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$here"

if [[ "${1:-}" == "clean" ]]; then
  rm -rf build lib
fi

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel

echo "built libraries in $here/lib:"
ls -1 lib/*.so 2>/dev/null || echo "  (none)"
