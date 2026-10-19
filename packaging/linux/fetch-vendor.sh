#!/usr/bin/env bash
# Downloads the two build-time tools that are not in distribution packages into vendor/
# (ignored by git): recent Vulkan-Headers and appimagetool. Nothing is installed system-wide.
#   bash packaging/linux/fetch-vendor.sh
# pkgextract and the optional DLSS files are not fetched here: see README.md.
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
mkdir -p "$here/vendor"

if [[ ! -d $here/vendor/Vulkan-Headers ]]; then
    git clone --depth 1 https://github.com/KhronosGroup/Vulkan-Headers "$here/vendor/Vulkan-Headers"
fi
echo "Vulkan-Headers: $(grep -m1 'define VK_HEADER_VERSION ' "$here/vendor/Vulkan-Headers/include/vulkan/vulkan_core.h")"

tool=$here/vendor/appimagetool-x86_64.AppImage
if [[ ! -x $tool ]]; then
    curl -fL -o "$tool" https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x "$tool"
fi
echo "appimagetool: $tool"
