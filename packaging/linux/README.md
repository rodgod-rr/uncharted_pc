# Uncharted: The Nathan Drake Collection on Linux (experimental)

A native Linux build of this port, packaged as an AppImage. It is the same code as the
Windows release; the changes that make it build and run on Linux are in the commits of this
branch (see "What changed").

**You need your own decrypted dump or `.pkg` files of the collection. No game files are included
or distributed.** This project is not affiliated with Sony Interactive Entertainment or Naughty Dog.

## Status

Tested on one machine only:

| | |
|---|---|
| OS | Fedora 44, kernel 7.2, KDE Plasma (Wayland) |
| CPU / GPU | Intel Core i5-13450HX / NVIDIA GeForce RTX 4050 Laptop (6 GB), driver 615.78 |
| Game | CUSA02320 base game + update 1.02, `u1` (`eboot.bin`) |

What works there:

- builds with GCC and runs; **Uncharted 1 plays at 50-60 FPS** with the DLSS upscaler;
- installing the game, update and add-ons from `.pkg` files (`--install-pkg`);
- the in-game settings menu (Insert).

**Not tested:** Uncharted 2 and 3 (`u2`, `u3`), AMD and Intel GPUs, other distributions,
sessions longer than about 40 minutes, controllers.

Known problems:

- **FSR frame generation broke the picture on the NVIDIA proprietary driver**, and during the same
  minute the kernel log filled with `NVRM: dmaAllocMapping_GM107: can't alloc VA space` (BAR1
  allocation failures, ~600,000 messages in 40 s). The two were observed together; the cause was not
  investigated. Leave frame generation off. DLSS frame generation is not available (see "DLSS").
- Switching the upscaler while playing (to FSR 4 without its assets) fell back to FSR 3.1 and then
  logged `FSR 3 context creation failed`. Restart the game after changing the upscaler or frame
  generation; not investigated further.
- One crash after ~40 minutes, right after a checkpoint save:
  `ASSERTION: iSubMesh < m_numSubMeshInstances` (ndlib/render/ngen/mesh.h:1361) followed by a
  null access. Not investigated; it did not show a driver error at that moment.
- Video memory use grew to about 5 GiB of 6 GiB during a long session.

Performance note (laptops): the game keeps about 6-8 cores busy, mostly its own job workers
polling for work. On a Dell G15 5530, in our tests, the CPU hit 100 °C and the clocks then fell to about 1-1.8 GHz,
dropping the frame rate to ~20 FPS; the `performance` platform profile together with the
`alienware_wmi` `fanN_boost` attribute kept the clocks up. This is specific to that laptop and the
cause (firmware power management) was inferred, not confirmed.

## Build

Dependencies (Fedora; `ffmpeg-devel` is from RPM Fusion):

```bash
bash packaging/linux/deps-fedora.sh list      # what it installs
bash packaging/linux/deps-fedora.sh install   # sudo dnf install ...
bash packaging/linux/deps-fedora.sh remove    # takes the same packages out again
```

Other distributions need the equivalents of that list (Vulkan 1.3 headers and loader, SDL3,
Boost, fmt, xxhash, glslang, SPIRV, Zydis, protobuf, nlohmann-json, OpenSSL, zlib, X11/Wayland,
VMA, xbyak, FFmpeg, miniupnpc).

Then fetch the two tools that are not packaged and build:

```bash
bash packaging/linux/fetch-vendor.sh    # Vulkan-Headers + appimagetool into packaging/linux/vendor/
bash packaging/linux/build.sh           # clones the submodules, builds out/bb-probe and out/gpu/libbbgpu.so
```

`build.sh` only changes the compiler's search path for this build:

- Zydis and protobuf have pkg-config files on Fedora but no CMake config: `shims/` provides them;
- recent Vulkan-Headers are put first (the code needs `VK_VALVE_shader_mixed_float_dot_product`);
- the vendored `magic_enum` is used because the code includes `<magic_enum/magic_enum.hpp>`.

## AppImage

```bash
bash packaging/linux/make-appimage.sh      # dist/Uncharted-x86_64.AppImage
```

It uses the system `python3` at run time (the machine that builds it also needs Pillow, for the
icon) and bundles the shared libraries that are not part of glibc, the GPU driver or the window system. It is built against
the glibc of the machine that builds it, so it runs on that distribution version or newer.

Optional inputs in `packaging/linux/vendor/` (ignored by git):

- `pkgextract`: enables `--install-pkg`. Build it from
  [paulomanrique/ps4-pkg-extractor](https://github.com/paulomanrique/ps4-pkg-extractor) (Unlicense).
- `dlss/`: enables DLSS, see below.

## Use

Install from packages (the game, the update and add-ons are told apart by their headers):

```bash
./Uncharted-x86_64.AppImage --install-pkg ~/Games/Uncharted GAME.pkg UPDATE.pkg [DLC.pkg ...]
```

It prints `GAME_DIR=...` at the end. Play:

```bash
./Uncharted-x86_64.AppImage ~/Games/Uncharted/CUSA02320 u1     # u1, u2 or u3
```

Settings and saves are kept in `~/.local/share/uncharted` (`BB_DATA_DIR`). Settings are edited
in the game (Insert) or in `bbport.ini` there.

## DLSS

DLSS needs two files beside `bb-probe` (the AppImage puts them there when they are in
`vendor/dlss/`): the bridge `libbbport_dlss.so` and NVIDIA's `libnvidia-ngx-dlss.so.<version>`
from [NVIDIA/DLSS](https://github.com/NVIDIA/DLSS) (`lib/Linux_x86_64/rel`), with its license text
as `NVIDIA-DLSS-LICENSE.txt`. **Do not commit NVIDIA's library**: it has its own license.

The loader in `vk_dlss.cpp` accepts bridge ABI 1 and 2. The bridge used for testing was built for
the Bloodborne port (ABI 1): upscaling works ("DLSS: ready"); DLSS frame generation needs ABI 2
and is not covered here.

## What changed (relative to the Windows code)

- `src/runtime_*.c`: build cleanly with GCC `-Werror`.
- GPU library: Win32-only debug code in `vk_scheduler.cpp` got Linux equivalents, one
  `vk::Extent2D` assignment GCC rejects, and `miniupnpc` is linked on Linux.
- `run.py` runs on Linux (PID wait, probe name, command quoting).
- `vk_dlss.cpp` has the Linux loader (`dlopen`).
- `scripts/pkg_install.py` installs from `.pkg` files.
- `packaging/linux/`: this directory.

## License

GPL-2.0-or-later like the rest of the project. The AppImage bundles other libraries under their
own licenses; NVIDIA's DLSS library is only bundled by you, under NVIDIA's license.
