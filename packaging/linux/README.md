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
| Game | CUSA02320 base game + update 1.02: `u1` (`eboot.bin`) played, `u2` and `u3` only started |

What works there:

- builds with GCC and runs; **Uncharted 1 plays at 50-60 FPS** with the DLSS upscaler, and at 120 FPS with
  DLSS frame generation;
- **Uncharted 2 and 3 start and render at 120 FPS** with DLSS frame generation. Only the opening of each was
  run (a minute or two), so "playable" is not established for them;
- installing the game, update and add-ons from `.pkg` files (`--install-pkg`);
- the in-game settings menu (Insert).

**Not tested:** longer sessions of Uncharted 2 and 3, AMD and Intel GPUs, other distributions,
sessions longer than about 40 minutes, controllers.

Known problems:

- **FSR 3 frame generation broke the picture on the NVIDIA proprietary driver**, and during the same
  minute the kernel log filled with `NVRM: dmaAllocMapping_GM107: can't alloc VA space` (BAR1
  allocation failures, ~600,000 messages in 40 s). The two were observed together; the cause was not
  investigated. Use DLSS frame generation instead on RTX 40+ (see "DLSS").
- Switching the upscaler while playing (to FSR 4 without its assets) fell back to FSR 3.1 and then
  logged `FSR 3 context creation failed`. Restart the game after changing the upscaler or frame
  generation; not investigated further.
- Two crashes of Uncharted 1, one after ~40 minutes and one after ~68 minutes, both right after a
  checkpoint save (`SaveWorker` / `save data ... mounted` in the log, the second one after a cutscene):
  `ASSERTION: iSubMesh < m_numSubMeshInstances` (ndlib/render/ngen/mesh.h:1361) followed by a
  null access (guest fault at 0x547c41 the second time). Not investigated; no driver error or OOM in the
  kernel log. The first one happened before the optional spin backoff existed, the second one with it
  enabled (level 10); whether it is related was not tested (it would need a run with `BB_SPIN_BACKOFF=0`).
- Video memory use grew to about 5 GiB of 6 GiB during a long session.

Performance note (laptops): the game keeps about 6-8 cores busy, mostly its own job workers
polling for work (see "Idle workers: spin backoff" below). On a Dell G15 5530, in our tests, the CPU hit
100 °C and the clocks then fell to about 1-1.8 GHz, dropping the frame rate to ~20 FPS; the `performance`
platform profile together with the `alienware_wmi` `fanN_boost` attribute kept the clocks up. This is
specific to that laptop and the cause (firmware power management) was inferred, not confirmed.

## Idle workers: spin backoff (optional)

The job workers of the games (`NdJobWorker`) poll their queues in a `pause` loop and never sleep (on a PS4
each has a core of its own). A `perf` profile of Uncharted 1 showed about 57% of the CPU time in that loop. On a
laptop this only costs power and heat, so `scripts/spin_backoff.py` can patch it: the worker still spins for the
first N empty polls, so it reacts at once when work arrives, and sleeps M microseconds per poll after that.

- The loop is found by its bytes (not by an address), so one script covers `eboot.bin` (u1), `big2` (u2) and
  `big3` (u3). Nothing is written unless every byte matches; otherwise the game starts unpatched. Only the
  `jmp rel32` after each `pause` is rewritten, and the routine lives in the zero padding at the end of the text.
- It is off by default in `run.py`: `BB_SPIN_BACKOFF=1` turns it on, `BB_SPIN_AFTER` and `BB_SPIN_SLEEP_US` set N
  and M. The AppImage built by `make-appimage.sh` turns it on with N=1 and M=1000 (`BB_SPIN_BACKOFF=0` turns it off).

Measured on the machine above (CPU cores used by the game, `balanced` profile, opening scenes, 15-20 s each):

| | without | with N=30, M=200 us |
|---|---|---|
| Uncharted 1 | 6.2 | 2.2 |
| Uncharted 2 | 5.9 | 2.3 |
| Uncharted 3 | 6.0 | 2.4 |

CPU temperature went down about 4-5 °C and, in one comparison, the package no longer touched 94 °C. Settings from
N=30, M=200 us up to N=1, M=1000 us were played at 60 FPS in Uncharted 1 without noticeable drops; longer sleeps
(2-4 ms) used no less CPU and add latency, so they are not recommended. Not evaluated: long sessions of
Uncharted 2 and 3, other CPUs, and whether the patch relates to the crash described above.

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
- `dlss/`: enables DLSS and its frame generation, made by `build-dlss-bridge.sh` (see below).

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

`build-dlss-bridge.sh` downloads NVIDIA's [DLSS SDK](https://github.com/NVIDIA/DLSS) (public; only the
headers, `libnvsdk_ngx.a` and the Linux `libnvidia-ngx-dlss` / `libnvidia-ngx-dlssg` libraries, ~100 MB),
builds the bridge `libbbport_dlss.so` (ABI 2: Super Resolution and Frame Generation) and collects the
files in `vendor/dlss/`, which `make-appimage.sh` bundles next to `bb-probe`:

```bash
bash packaging/linux/build-dlss-bridge.sh
bash packaging/linux/make-appimage.sh
```

**Do not commit NVIDIA's libraries**: they have their own license (`NVIDIA-DLSS-LICENSE.txt` is copied
next to them). Frame Generation needs an RTX 40 or newer GPU and a recent NVIDIA driver.

Status: on the RTX 4050 Laptop above the log reports "DLSS: Frame Generation available (up to 2x)", and
choosing DLSS frame generation in the in-game menu (Insert) showed 120 FPS on screen in a short test, with
no NVIDIA driver errors in the kernel log during it. Longer sessions, latency and image artifacts were not
evaluated. A bridge of ABI 1 (for example the Bloodborne port's) still works for upscaling only.

## What changed (relative to the Windows code)

- `src/runtime_*.c`: build cleanly with GCC `-Werror`.
- GPU library: Win32-only debug code in `vk_scheduler.cpp` got Linux equivalents, one
  `vk::Extent2D` assignment GCC rejects, and `miniupnpc` is linked on Linux.
- `run.py` runs on Linux (PID wait, probe name, command quoting).
- `vk_dlss.cpp` has the Linux loader (`dlopen`); `gpu/dlss_bridge` builds on Linux too.
- `scripts/pkg_install.py` installs from `.pkg` files.
- `packaging/linux/`: this directory.

## License

GPL-2.0-or-later like the rest of the project. The AppImage bundles other libraries under their
own licenses; NVIDIA's DLSS library is only bundled by you, under NVIDIA's license.
