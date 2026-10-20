#!/bin/zsh
# Runs the Android link code (LinkCrypto, LinkClient) on the bundled JDK against the real Mac link server.
set -euo pipefail
cd "${0:A:h:h}"
jdk="$PWD/build/tools/jdk-21.0.12.1+1/Contents/Home"
classes="${TMPDIR:-/private/tmp/}ascend-link-interop"
rm -rf "$classes"; mkdir -p "$classes"
"$jdk/bin/javac" -d "$classes" \
  android/bridge/src/com/abdul/ascend/bridge/LinkCrypto.java \
  android/bridge/src/com/abdul/ascend/bridge/LinkClient.java \
  android/bridge/test/com/abdul/ascend/bridge/InteropMain.java
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/private/tmp/}ascend-module-cache"
ASCEND_JAVA_INTEROP="$jdk/bin/java" ASCEND_JAVA_CP="$classes" \
  swift run --disable-sandbox --cache-path "${TMPDIR:-/private/tmp/}ascend-swift-cache" AscendChecks
