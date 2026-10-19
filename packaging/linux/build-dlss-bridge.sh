#!/usr/bin/env bash
# Builds the DLSS bridge (libbbport_dlss.so, ABI 2: Super Resolution and Frame Generation) against
# NVIDIA's DLSS SDK and collects the files make-appimage.sh bundles, in vendor/dlss/ (git-ignored).
#   bash packaging/linux/build-dlss-bridge.sh
#
# Downloads from github.com/NVIDIA/DLSS (public; NVIDIA's own license, see its LICENSE.txt): only the
# headers, libnvsdk_ngx.a and the Linux libnvidia-ngx-dlss / libnvidia-ngx-dlssg libraries, ~100 MB.
# Frame Generation needs an RTX 40 or newer GPU and a recent NVIDIA driver. NVIDIA's libraries stay
# on this machine: do not commit them.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
repo=$(cd -- "$here/../.." && pwd)
sdk=$here/vendor/dlss-sdk
out=$here/vendor/dlss

if [[ ! -f $sdk/include/nvsdk_ngx_vk.h ]]; then
    rm -rf "$sdk"
    git clone -q --depth 1 --filter=blob:none --sparse https://github.com/NVIDIA/DLSS "$sdk"
    git -C "$sdk" sparse-checkout set --no-cone '/LICENSE.txt' '/include/' \
        '/lib/Linux_x86_64/libnvsdk_ngx.a' '/lib/Linux_x86_64/rel/libnvidia-ngx-dlss.so.*' \
        '/lib/Linux_x86_64/rel/libnvidia-ngx-dlssg.so.*'
fi
echo "DLSS SDK: $(git -C "$sdk" log -1 --format='%h %cd' --date=short)"

cmake -S "$repo/gpu/dlss_bridge" -B "$repo/out/dlss-bridge" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DDLSS_SDK_ROOT="$sdk" > /dev/null
ninja -C "$repo/out/dlss-bridge"

rm -rf "$out"
mkdir -p "$out"
install -m755 "$repo/out/dlss-bridge/libbbport_dlss.so" "$out/"
install -m755 "$sdk"/lib/Linux_x86_64/rel/libnvidia-ngx-dlss*.so.* "$out/"
cp "$sdk/LICENSE.txt" "$out/NVIDIA-DLSS-LICENSE.txt"
ls -l "$out"
