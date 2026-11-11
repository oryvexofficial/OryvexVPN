#!/usr/bin/env bash
# Builds the bypass engine (oryvex-bypass), the C program oryvexcore runs for --bypass.
#
# usage (from oryvexcore/bypass/):
#   bash build.sh native  <outdir>                 this machine (cc, or CC=...)
#   bash build.sh windows <x86_64|x86> <outdir>    oryvex-bypass.exe, cross-built with zig cc
#   bash build.sh android <abi> <outdir>           liboryvex_bypass.so (an executable; Android only
#                                                  lets an app exec files from its native lib dir)
#
# Android needs ANDROID_NDK_HOME (r27+). API level: ANDROID_API (default 21).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC=("$HERE"/src/*.c)
CFLAGS=(-std=c11 -O2 -Wall)

kind="${1:-native}"
shift || true

case "$kind" in
  native)
    out="${1:?outdir}"; mkdir -p "$out"
    "${CC:-cc}" "${CFLAGS[@]}" -pthread -o "$out/oryvex-bypass" "${SRC[@]}"
    echo "-> $out/oryvex-bypass"
    ;;
  windows)
    arch="${1:?x86_64 or x86}"; out="${2:?outdir}"; mkdir -p "$out"
    case "$arch" in x86_64|x86) ;; *) echo "unknown arch $arch" >&2; exit 2 ;; esac
    zig cc -target "$arch-windows-gnu" "${CFLAGS[@]}" -s -o "$out/oryvex-bypass.exe" "${SRC[@]}" -lws2_32 -liphlpapi
    echo "-> $out/oryvex-bypass.exe"
    ;;
  android)
    abi="${1:?abi}"; out="${2:?outdir}"; mkdir -p "$out"
    : "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME is not set}"
    api="${ANDROID_API:-21}"
    case "$abi" in
      arm64-v8a) triple=aarch64-linux-android ;;
      armeabi-v7a) triple=armv7a-linux-androideabi ;;
      x86_64) triple=x86_64-linux-android ;;
      x86) triple=i686-linux-android ;;
      *) echo "unknown abi $abi" >&2; exit 2 ;;
    esac
    host="$(ls "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" | head -n1)"
    cc="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$host/bin/${triple}${api}-clang"
    "$cc" "${CFLAGS[@]}" -fPIE -pie -Wl,-z,max-page-size=16384 -s -o "$out/liboryvex_bypass.so" "${SRC[@]}"
    echo "-> $out/liboryvex_bypass.so"
    ;;
  *) echo "usage: $0 native|windows|android ..." >&2; exit 2 ;;
esac
