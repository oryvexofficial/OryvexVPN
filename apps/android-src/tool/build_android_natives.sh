#!/usr/bin/env bash
# Builds the native pieces the Android app ships and drops them into
# apps/android-src/android/app/src/main/jniLibs/<abi>/:
#
#   liboryvexcore_cli.so      the OryvexCore core, an executable (Android only lets apps exec
#                             files from their native library dir, hence the lib*.so name)
#   libhev-socks5-tunnel.so   tun -> SOCKS5 engine for whole-device VPN mode
#
# usage:
#   tool/build_android_natives.sh core <abi> [<abi>...]   # arm64-v8a armeabi-v7a x86_64
#   tool/build_android_natives.sh tun  [<abi>...]
#   tool/build_android_natives.sh all
#
# needs: ANDROID_NDK_HOME (r27+; r28 recommended for 16 KB pages), Rust stable with the android
# targets, cargo-ndk, CMake, git, python3.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
APP="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$APP/../.." && pwd)"
JNI="$APP/android/app/src/main/jniLibs"
API="${ANDROID_API:-21}"
ALL_ABIS=(arm64-v8a armeabi-v7a x86_64)
# tor-exit-country lets the Tor route pick its exit country (auto / fastest / de,...). Should that
# feature ever fail to build, the core is built again with plain tor (set CORE_FEATURES_STRICT=1
# to fail instead).
CORE_FEATURES="${CORE_FEATURES:-tor tor-exit-country}"
CORE_FALLBACK_FEATURES="${CORE_FALLBACK_FEATURES:-tor}"
HEV_REPO="${HEV_REPO:-https://github.com/heiher/hev-socks5-tunnel}"
HEV_REF="${HEV_REF:-}"

: "${ANDROID_NDK_HOME:=${ANDROID_NDK_ROOT:-}}"
if [ -z "$ANDROID_NDK_HOME" ] || [ ! -d "$ANDROID_NDK_HOME" ]; then
  echo "ANDROID_NDK_HOME is not set to an NDK" >&2
  exit 1
fi
export ANDROID_NDK_HOME ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"

triple_of() {
  case "$1" in
    arm64-v8a) echo aarch64-linux-android ;;
    armeabi-v7a) echo armv7-linux-androideabi ;;
    x86_64) echo x86_64-linux-android ;;
    x86) echo i686-linux-android ;;
    *) echo "unknown abi $1" >&2; exit 1 ;;
  esac
}

build_core() {
  local abi="$1" triple under bin
  triple="$(triple_of "$abi")"
  under="$(echo "$triple" | tr '-' '_')"
  echo "== core for $abi ($triple, API $API)"
  (
    cd "$ROOT/oryvexcore"
    # Link libc++ statically so the executable needs nothing but the system's own libs.
    export "BORING_BSSL_RUST_CPPLIB_${under}=static:-bundle=c++"
    # 16 KB page alignment for Android 15+ devices that use it (NDK r28 does this by default).
    export RUSTFLAGS="${RUSTFLAGS:-} -C link-arg=-Wl,-z,max-page-size=16384"
    local feat=()
    [ -n "$CORE_FEATURES" ] && feat=(--features "$CORE_FEATURES")
    if ! cargo ndk -t "$abi" --platform "$API" build --release "${feat[@]}"; then
      if [ "${CORE_FEATURES_STRICT:-0}" = 1 ] || [ "$CORE_FEATURES" = "$CORE_FALLBACK_FEATURES" ]; then
        exit 1
      fi
      echo "::warning::core features '$CORE_FEATURES' did not build for $abi; building with '$CORE_FALLBACK_FEATURES' (no Tor exit-country choice)"
      cargo ndk -t "$abi" --platform "$API" build --release --features "$CORE_FALLBACK_FEATURES"
    fi
  )
  bin="$ROOT/oryvexcore/target/$triple/release/oryvexcore"
  if readelf -d "$bin" 2>/dev/null | grep -q 'libc++_shared.so'; then
    echo "ERROR: core still needs libc++_shared.so" >&2
    exit 1
  fi
  mkdir -p "$JNI/$abi"
  cp "$bin" "$JNI/$abi/liboryvexcore_cli.so"
  chmod 755 "$JNI/$abi/liboryvexcore_cli.so"
  echo "   -> $JNI/$abi/liboryvexcore_cli.so ($(du -h "$JNI/$abi/liboryvexcore_cli.so" | cut -f1))"
}

build_tun() {
  local abis=("$@")
  [ ${#abis[@]} -eq 0 ] && abis=("${ALL_ABIS[@]}")
  local work
  work="$(mktemp -d)"
  echo "== hev-socks5-tunnel for ${abis[*]}"
  mkdir -p "$work/jni"
  echo 'include $(call all-subdir-makefiles)' > "$work/jni/Android.mk"
  git clone --recursive --depth 1 ${HEV_REF:+--branch "$HEV_REF"} "$HEV_REPO" "$work/jni/hev-socks5-tunnel"

  python3 "$HERE/gen_tproxy_binding.py" \
    "$work/jni/hev-socks5-tunnel/src/hev-jni.c" \
    "$APP/android/app/src/main/java/hev/htproxy/TProxyService.java"

  local ok=0
  pushd "$work" >/dev/null
  for api in "$API" 24; do
    if "$ANDROID_NDK_HOME/ndk-build" \
        NDK_PROJECT_PATH=. \
        APP_BUILD_SCRIPT=jni/Android.mk \
        "APP_ABI=${abis[*]}" \
        "APP_PLATFORM=android-$api" \
        NDK_LIBS_OUT="$work/libs" \
        NDK_OUT="$work/obj" \
        "APP_CFLAGS=-O3 -DPKGNAME=hev/htproxy -DCLSNAME=TProxyService" \
        "APP_LDFLAGS=-Wl,--build-id=none -Wl,-z,max-page-size=16384" \
        -j"$(nproc 2>/dev/null || echo 2)"; then
      ok=1
      echo "   built for android-$api"
      break
    fi
    echo "   android-$api failed, retrying with a newer platform" >&2
  done
  popd >/dev/null
  if [ "$ok" != 1 ]; then
    echo "WARNING: hev-socks5-tunnel did not build; the app will run in proxy-only mode" >&2
    rm -rf "$work"
    return 0
  fi
  for abi in "${abis[@]}"; do
    mkdir -p "$JNI/$abi"
    cp "$work/libs/$abi/libhev-socks5-tunnel.so" "$JNI/$abi/"
    echo "   -> $JNI/$abi/libhev-socks5-tunnel.so"
  done
  rm -rf "$work"
}

cmd="${1:-all}"
shift || true
case "$cmd" in
  core)
    [ $# -eq 0 ] && set -- "${ALL_ABIS[@]}"
    for abi in "$@"; do build_core "$abi"; done
    ;;
  tun) build_tun "$@" ;;
  all)
    for abi in "${ALL_ABIS[@]}"; do build_core "$abi"; done
    build_tun "${ALL_ABIS[@]}"
    ;;
  *) echo "usage: $0 core|tun|all [abi...]" >&2; exit 2 ;;
esac
