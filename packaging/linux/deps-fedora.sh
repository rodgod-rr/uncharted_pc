#!/usr/bin/env bash
# Build dependencies of the Linux build on Fedora, installed or removed in one dnf transaction.
#   bash deps-fedora.sh install | remove | list
# ffmpeg-devel comes from RPM Fusion (the Fedora "-free" ffmpeg packages conflict with it).
set -euo pipefail
pkgs=(gcc-c++ cmake ninja-build SDL3-devel vulkan-headers vulkan-loader-devel boost-devel fmt-devel
  robin-map-devel xxhash-devel glslang-devel spirv-tools-devel spirv-headers-devel zydis-devel
  miniz-devel protobuf-devel json-devel openssl-devel zlib-ng-compat-devel libX11-devel
  libxcb-devel wayland-devel xorg-x11-proto-devel VulkanMemoryAllocator-devel xbyak-devel
  magic_enum-devel ffmpeg-devel miniupnpc-devel)
case ${1:-list} in
  install) sudo dnf install -y "${pkgs[@]}" ;;
  remove)  sudo dnf remove -y "${pkgs[@]}" ;;   # or: sudo dnf history undo <transaction id>
  list)    printf '%s\n' "${pkgs[@]}" ;;
  *)       echo 'usage: deps-fedora.sh install|remove|list' >&2; exit 2 ;;
esac
