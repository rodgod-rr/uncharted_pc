#!/usr/bin/env bash
# Builds dist/Uncharted-x86_64.AppImage from the current build (bash packaging/linux/build.sh).
# No Nix involved. The AppImage uses the system python3; the bundled libraries are only seen by
# bb-probe, through a small wrapper, so they cannot disturb python.
#
# Inputs in packaging/linux/vendor/ (ignored by git):
#   appimagetool-x86_64.AppImage   required (fetch-vendor.sh)
#   pkgextract                     optional: enables `--install-pkg` (see README.md)
#   dlss/                          optional: libbbport_dlss.so, libnvidia-ngx-dlss.so.*,
#                                  NVIDIA-DLSS-LICENSE.txt: enables DLSS (see README.md)
set -euo pipefail
here=$(cd -- "$(dirname -- "$0")" && pwd)
repo=$(cd -- "$here/../.." && pwd)
app=$repo/dist/AppDir
tool=$here/vendor/appimagetool-x86_64.AppImage
[[ -x $repo/out/bb-probe && -f $repo/out/gpu/libbbgpu.so ]] || { echo 'Build first: bash packaging/linux/build.sh' >&2; exit 1; }
[[ -x $tool ]] || { echo "Missing $tool: run packaging/linux/fetch-vendor.sh" >&2; exit 1; }

rm -rf "$app"
share=$app/usr/share/uncharted
mkdir -p "$share/bin/gpu" "$share/scripts" "$app/usr/lib"
install -m755 "$repo/out/bb-probe" "$share/bin/bb-probe-real"
install -m755 "$repo/out/bb-gpu-capabilities" "$share/bin/"
install -m755 "$repo/out/gpu/libbbgpu.so" "$share/bin/gpu/"
# bb-probe-real looks for libbbgpu.so in $ORIGIN/gpu; the wrapper gives the bundled libraries to it only.
cat > "$share/bin/bb-probe" <<'W'
#!/bin/sh
d=$(cd -- "$(dirname -- "$0")" && pwd)
export LD_LIBRARY_PATH="$d/../../../lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$d/bb-probe-real" "$@"
W
chmod +x "$share/bin/bb-probe"
cp "$repo/run.py" "$repo/LICENSE" "$share/"
cp "$repo"/scripts/{prepare,link_modules,link_libc,content_profile,pkg_install}.py "$share/scripts/"
[[ -x $here/vendor/pkgextract ]] && install -m755 "$here/vendor/pkgextract" "$share/bin/pkgextract"

# Optional DLSS: the bridge and NVIDIA's runtime library, found by vk_dlss.cpp beside bb-probe.
if [[ -f $here/vendor/dlss/libbbport_dlss.so ]]; then
    install -m755 "$here"/vendor/dlss/lib*.so* "$share/bin/"
    mkdir -p "$share/licenses" && cp "$here"/vendor/dlss/NVIDIA-DLSS-LICENSE.txt "$share/licenses/"
fi

# Libraries: everything except what must come from the system (glibc, GPU, window system, audio).
skip='^(linux-vdso|ld-linux|libc\.|libm\.|libdl\.|libpthread|librt\.|libresolv|libutil|libmvec|libgcc_s|libvulkan|libGL|libEGL|libGLX|libGLdispatch|libOpenCL|libdrm|libX11|libXau|libXext|libXfixes|libXrender|libxcb|libwayland|libudev|libsystemd|libasound|libpulse|libpipewire|libdbus|libselinux|libmount|libblkid|libcap\.|libva|libvdpau)'
ldd "$share/bin/bb-probe-real" "$share/bin/gpu/libbbgpu.so" "$share/bin/bb-gpu-capabilities" |
    awk '/=> \// {print $1, $3}' | sort -u | while read -r name path; do
        [[ $name =~ $skip ]] && continue
        install -m755 "$(readlink -f "$path")" "$app/usr/lib/$name"
    done

# The icon is generated (the repository ignores *.png): the largest image of the launcher's .ico.
python3 - "$repo/launcher/uncharted.ico" "$app/uncharted.png" <<'PY'
import sys
from PIL import Image
icon = Image.open(sys.argv[1])
icon.size = max(icon.ico.sizes())
icon.load()
icon.convert('RGBA').save(sys.argv[2])
PY
cat > "$app/uncharted.desktop" <<'D'
[Desktop Entry]
Type=Application
Name=Uncharted: The Nathan Drake Collection
Comment=Native Linux port of Uncharted 1, 2 and 3
Exec=AppRun
Icon=uncharted
Categories=Game;
Terminal=true
D
cat > "$app/AppRun" <<'A'
#!/usr/bin/env bash
# Play:    Uncharted-x86_64.AppImage GAME_DIR [u1|u2|u3] [bb-probe arguments...]
#          (or BB_GAME_DIR=GAME_DIR BB_EXE=u2 Uncharted-x86_64.AppImage)
# Install: Uncharted-x86_64.AppImage --install-pkg DEST_DIR GAME.pkg [UPDATE.pkg ...] [DLC.pkg ...]
here=$(cd -- "$(dirname -- "$0")" && pwd)
# Steam injects host libraries (its overlay) that break the bundled environment.
unset LD_PRELOAD LD_AUDIT PYTHONHOME PYTHONPATH
export DISABLE_VK_LAYER_VALVE_steam_overlay_1=1 DISABLE_VK_LAYER_VALVE_steam_fossilize_1=1
command -v python3 >/dev/null || { echo 'Install python3.' >&2; exit 1; }
if [[ ${1:-} == --install-pkg ]]; then
    [[ $# -ge 3 ]] || { echo "usage: ${APPIMAGE:-$0} --install-pkg DEST_DIR GAME.pkg [UPDATE.pkg ...] [DLC.pkg ...]" >&2; exit 2; }
    [[ -x $here/usr/share/uncharted/bin/pkgextract ]] || { echo 'This AppImage was built without pkgextract.' >&2; exit 1; }
    export BB_PKGEXTRACT="$here/usr/share/uncharted/bin/pkgextract"
    dest=$2; shift 2
    exec python3 "$here/usr/share/uncharted/scripts/pkg_install.py" --dest "$dest" "$@"
fi
if [[ $# -ge 1 && -d $1 ]]; then export BB_GAME_DIR=$1; shift; fi
if [[ ${1:-} =~ ^u[123]$ ]]; then export BB_EXE=$1; shift; fi
if [[ -z ${BB_GAME_DIR:-} ]]; then
    echo "usage: ${APPIMAGE:-$0} GAME_DIR [u1|u2|u3]   (the folder with eboot.bin)" >&2; exit 2
fi
export BB_DATA_DIR=${BB_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/uncharted}
mkdir -p "$BB_DATA_DIR"
export BB_PROBE="$here/usr/share/uncharted/bin/bb-probe"
exec python3 "$here/usr/share/uncharted/run.py" "$@"
A
chmod +x "$app/AppRun"
mkdir -p "$repo/dist"
ARCH=x86_64 "$tool" --appimage-extract-and-run "$app" "$repo/dist/Uncharted-x86_64.AppImage"
ls -lh "$repo/dist/Uncharted-x86_64.AppImage"
