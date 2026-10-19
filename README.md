# Return to Castle Wolfenstein (Single Player) - ARM64 / Metal port

A port of the GPL _Return to Castle Wolfenstein_ single-player source to modern
64-bit Apple platforms: **macOS on Apple Silicon (arm64)** with a choice of an
**OpenGL** or **Metal** renderer backend.

The original id Software release notes, license summary, and third-party code
attributions are preserved verbatim in [`README.txt`](README.txt). This file
documents the port only.

> This is an unofficial, work-in-progress port. Game data is **not** included and
> is still covered by the original RTCW EULA (see [`README.txt`](README.txt)).

## Status

- **macOS (arm64), OpenGL backend**: builds and runs.
- **macOS (arm64), Metal backend**: builds and runs via a GL-1.x-on-Metal
  translation shim (the engine's fixed-function renderer is unmodified; the
  `qgl*` entry points are routed to Metal).

The bulk of the work was making the 1999-era, 32-bit-assuming codebase correct
under LP64 and the Apple arm64 ABI. See [Porting notes](#porting-notes).

## Requirements

- Apple Silicon Mac (arm64).
- Xcode command-line tools, CMake ≥ 3.20.
- SDL2 (windowing, input, audio). Install via Homebrew:
  ```sh
  brew install cmake sdl2
  ```
  The build auto-detects SDL2 via `pkg-config`, falling back to the Homebrew
  path `/opt/homebrew/opt/sdl2`.
- A legitimate copy of the retail RTCW game data (`pak0.pk3`, `sp_pak*.pk3`,
  `mp_pak*.pk3`, …). RTCW is available on Steam:
  <http://store.steampowered.com/app/9010/>.

## Building

The project builds an engine executable (`wolfsp`) plus three dynamically
loaded game modules (`qagame.dylib`, `cgame.dylib`, `ui.dylib`).

### OpenGL backend (default)

```sh
cmake -S . -B build -DUSE_METAL=OFF
cmake --build build -j
```

### Metal backend

```sh
cmake -S . -B build-metal -DUSE_METAL=ON
cmake --build build-metal -j
```

Build type defaults to `Release` and architecture to `arm64` if not overridden.

## Running

The engine loads its game modules and reads game data from the `main/`
directory next to the base path. Place the retail `.pk3` files **and** the three
freshly built module dylibs together in `main/`:

```sh
cp build-metal/qagame.dylib build-metal/cgame.dylib build-metal/ui.dylib main/
# copy pak0.pk3 / sp_pak*.pk3 / mp_pak*.pk3 from your retail install into main/
./build-metal/wolfsp
```

Run the OpenGL build the same way using `./build/wolfsp`.

> Keep the module dylibs in sync with the engine you run, a stale `*.dylib` in
> `main/` from a previous build is a common source of confusion.

## Renderer backends

The renderer itself is the original fixed-function GL-1.x code. `USE_METAL`
selects the platform/renderer glue:

| Backend                  | Platform glue                                    | Frameworks                          |
| ------------------------ | ------------------------------------------------ | ----------------------------------- |
| OpenGL (`USE_METAL=OFF`) | `src/sdl/sdl_glimp.c`                            | `OpenGL`                            |
| Metal (`USE_METAL=ON`)   | `src/metal/mtl_glimp.mm` + `src/metal/mtl_gl.mm` | `Metal`, `QuartzCore`, `Foundation` |

The Metal path consists of:

- `mtl_glimp.mm`: Metal device/`CAMetalLayer` creation and windowing (via SDL2).
- `mtl_gl.mm`: a GL-on-Metal shim that implements the `qgl*` function pointers
  (pipelines, buffers, textures) the engine expects.
- `mtl_local.h`: shared ObjC++ state between the two.

The Metal sources are compiled with ARC (`-fobjc-arc`) so per-draw buffers and
replaced textures are released automatically, and with `-fno-operator-names`
because `tr_local.h` uses `or` as an identifier.

### Added cvars

- `r_metalHud` _(archived, latched)_ — intended to enable Apple's Metal
  Performance HUD (FPS / frame-time / GPU-memory overlay) at launch via
  `+set r_metalHud 1`. **Note:** the HUD is currently force-disabled in
  `src/metal/mtl_glimp.mm` regardless of this cvar; see the comment there to
  re-enable it.

## Porting notes

This port is primarily a correctness exercise against LP64 and the Apple arm64
ABI. Notable changes (see `git log` for the full history):

- **Syscall / VM ABI**: 64-bit (LP64) syscall conversion between the engine and
  the game/cgame/ui modules; the x86 QVM JIT (`vm_x86.c`) is replaced by a
  no-JIT stub (modules are loaded as native dylibs via `dlopen`).
- **Variadic ABI**: `VM_Call` into the modules was going through the variadic
  calling convention, which passes arguments differently on Apple arm64; fixed
  to a fixed-arity call so modules receive correct arguments.
- **LP64 truncations**: numerous `long`/pointer-vs-`int` truncations fixed:
  MD4 checksums (`UINT4` was 8 bytes on LP64), RoQ cinematic motion-comp offsets,
  the AAS routing cache (`.rcd`) rejecting incompatible 32-bit caches, and a
  `drawSurf` sort that assumed an 8-byte struct.
- **arm64 stability fixes**: argument-buffer clobbering in `CG_Argv`/`UI_Argv`,
  dangling `client->gentity` and cached `modelInfo` pointers across game-VM
  restart (map_restart / loadgame), and SMP/`r_smp` command-buffer crashes.
- **Build system**: the original VC++ / `cons` build is replaced by CMake with
  an SDL2 platform layer; `-fgnu89-inline` preserves the codebase's gnu89 inline
  semantics.

The game logic, assets, and network protocol are unchanged.

## License

GPLv2 (with id Software's additional terms), see [`COPYING.txt`](COPYING.txt)
and the LICENSE / excluded-code sections in [`README.txt`](README.txt). This
port is distributed under the same terms.
