#!/usr/bin/env bash
# Builds the Linux binaries (out/bb-probe, out/gpu/libbbgpu.so) with GCC, without PGO/LTO.
# Nothing is installed system-wide: the shims and the Vulkan headers below are only put on
# the compiler's search path for this build.
#
#   bash packaging/linux/build.sh
#
# Needs the packages of deps-fedora.sh (or your distribution's equivalents); it fetches the git
# submodules itself.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
repo=$(cd -- "$here/../.." && pwd)

# The include path below needs the vendored magic_enum, so fetch the submodules first
# (the repository's build.sh would do it, but only after this script has set the path up).
if [[ ! -f $repo/gpu/third_party/magic_enum/include/magic_enum/magic_enum.hpp ||
      ! -f $repo/gpu/third_party/imgui/imgui.h ]]; then
    git -C "$repo" submodule update --init --recursive
fi

# Zydis and protobuf only ship pkg-config files on Fedora: CMake finds them through these shims.
export CMAKE_PREFIX_PATH="$here/shims${CMAKE_PREFIX_PATH:+:$CMAKE_PREFIX_PATH}"

# Extra include directories, only the ones that exist on this machine:
#  - vendor/Vulkan-Headers: the code uses extensions newer than some distributions' headers
#    (VK_VALVE_shader_mixed_float_dot_product); see README.md for how to fetch it;
#  - the vendored magic_enum, which the code includes as <magic_enum/magic_enum.hpp>
#    (Fedora's package installs it flat);
#  - miniupnpc and ffmpeg, which Fedora installs in a subdirectory of /usr/include.
inc=""
for dir in "$here/vendor/Vulkan-Headers/include" "$repo/gpu/third_party/magic_enum/include" \
           /usr/include/miniupnpc /usr/include/ffmpeg; do
    [[ -d $dir ]] && inc="${inc:+$inc:}$dir"
done
export CPLUS_INCLUDE_PATH="$inc${CPLUS_INCLUDE_PATH:+:$CPLUS_INCLUDE_PATH}"
export C_INCLUDE_PATH="$inc${C_INCLUDE_PATH:+:$C_INCLUDE_PATH}"

export BB_PGO=${BB_PGO:-off} BB_LTO=${BB_LTO:-OFF}

# Parallel compile jobs. ninja's default (cores + 2) can exhaust memory: one job compiling the
# GPU library's heaviest C++ files takes 1-2 GiB, and a 16 GiB machine with 18 jobs ran out of RAM
# and swap and had to be rebooted. Default: one job per 2.5 GiB of available memory, at most one
# per core. Override with BB_JOBS=N.
cores=$(nproc)
avail_kib=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
jobs=${BB_JOBS:-$(( avail_kib / 2621440 ))}
(( jobs > cores )) && jobs=$cores
(( jobs < 1 )) && jobs=1
echo "Linux build: $jobs parallel jobs ($cores cores, $((avail_kib / 1048576)) GiB available; BB_JOBS=N to change)"

# The repository's build.sh calls ninja without -j: put a ninja in front that adds it.
real_ninja=$(command -v ninja) || { echo 'ninja not found (see deps-fedora.sh)' >&2; exit 1; }
shim=$(mktemp -d)
trap 'rm -rf "$shim"' EXIT
printf '#!/bin/sh\nexec "%s" -j %s "$@"\n' "$real_ninja" "$jobs" > "$shim/ninja"
chmod +x "$shim/ninja"
PATH="$shim:$PATH"

cd "$repo"
bash build.sh "$@"
