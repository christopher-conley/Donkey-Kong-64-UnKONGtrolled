# Donkey Kong 64: UnKONGtrolled

A PC port of Donkey Kong 64, forked from [Donkey Kong 64 Rekongpiled](https://github.com/Rainchus/Donkey-Kong-64-Recompiled), maintained with maximum AI involvement out of pure, unadulterated spite. 🦍

This project uses [N64: Recompiled](https://github.com/Mr-Wiseguy/N64Recomp) to **statically recompile** Donkey Kong 64 into a native PC port with many new features and enhancements, and [RT64](https://github.com/rt64/rt64) as its rendering engine.

> **This repository and its releases do not contain game assets. The original game is required to build or run this project.**

---

## Why Does This Fork Exist?

The upstream project made the decision to combine several control settings into a single setting, with no way to separate or configure them individually. A contributor submitted a pull request with a proper fix. The upstream maintainers closed it with an accusation of AI-generated code — an accusation that was false — and did not engage with the substance of the fix.

Spite is a very powerful motivator.

This fork exists to apply that fix, and to continue development with the explicit and enthusiastic use of AI tooling. The name *UnKONGtrolled* was chosen by **Kagi Assistant** on September 20, 2026 — making it the first AI contributor to this repository. The full lore is documented in [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Table of Contents
* [System Requirements](#system-requirements)
* [Features](#features)
  * [Fully Intact N64 Effects](#fully-intact-n64-effects)
  * [Easy-to-Use Menus](#easy-to-use-menus)
  * [High Framerate Support](#high-framerate-support)
  * [Widescreen and Ultrawide Support](#widescreen-and-ultrawide-support)
  * [Additional Control Options](#additional-control-options)
  * [Low Input Lag](#low-input-lag)
  * [Instant Load Times](#instant-load-times)
  * [Linux and Steam Deck Support](#linux-and-steam-deck-support)
* [FAQ](#faq)
* [Known Issues](#known-issues)
* [Building](#building)
* [Contributing](#contributing)
* [Libraries Used and Projects Referenced](#libraries-used-and-projects-referenced)

---

## System Requirements

A GPU supporting Direct3D 12.0 (Shader Model 6) or Vulkan 1.2 is required. The oldest GPUs that should be supported for each vendor are:

* NVIDIA GeForce GT 630
* AMD Radeon HD 7750 (2012, not the RX 7000 series) and newer
* Intel HD 510 (Skylake)

A CPU supporting the AVX instruction set is also required (Intel Core 2000 series or AMD Bulldozer and newer).

If you experience crashes on startup, make sure your graphics drivers are fully up to date.

---

## Features

#### Fully Intact N64 Effects
All graphical effects are rendered exactly as they appeared on the N64. No workarounds or hacks were used to replicate them — modifications are made only for enhancement purposes such as widescreen support.

#### Easy-to-Use Menus
Gameplay, graphics, input, and audio settings can all be configured through the in-game config menu, fully usable with mouse, controller, or keyboard.

#### High Framerate Support
Play at any framerate you want. Game objects, terrain, texture scrolling, screen effects, and most HUD elements all render at high framerates. By default the project runs at your monitor's refresh rate, but you can lock it to the original N64 framerate if you prefer. **Changing framerate has no effect on gameplay.**

> **Note:** External framerate limiters (e.g. NVIDIA Control Panel) can cause stuttering. Use the in-game framerate slider instead.

#### Widescreen and Ultrawide Support
Any aspect ratio is supported, with most effects adjusted to work correctly in widescreen. The HUD can be positioned at 16:9 when using ultrawide aspect ratios.

> **Note:** Some animation quirks may appear at screen edges in certain cutscenes at very wide aspect ratios.

#### Additional Control Options
Set your stick deadzone to your liking, and independently adjust X and Y axis inversion for aiming — *as separate, individual settings, the way God intended.*

#### Low Input Lag
Optimized to minimize input lag, making the game feel more responsive than the original hardware.

#### Instant Load Times
Saving, loading, transitioning between areas, and pausing are all effectively instantaneous on modern hardware.

#### Linux and Steam Deck Support
A Linux binary is available for most up-to-date distros, including Steam Deck.

To play on Steam Deck: extract the Linux build, then in Desktop Mode right-click the `DK64UnKONGtrolled` executable and select "Add to Steam." Return to Gaming Mode and configure controls as needed.

---

## FAQ

#### What is static recompilation?
Static recompilation is the process of automatically [translating an application from one platform to another](https://www.youtube.com/watch?v=lMGu6Ng_3yA&t=55s). For full details on how this project's recompilation works, see [N64: Recompiled](https://github.com/Mr-Wiseguy/N64Recomp).

#### How is this related to the decompilation project?
This project is not based on decompiled source code. Static recompilation bypasses the need for decompiled source when making a port. However, the reverse engineering work done by the decompilation team was invaluable for certain enhancements — the project uses headers and some function definitions from the decompilation project for this purpose.

#### Where is the save file stored?
- **Windows:** `%LOCALAPPDATA%\DK64UnKONGtrolled\saves`
- **Linux:** `~/.config/DK64UnKONGtrolled/saves`

If you previously used DK64: Rekongpiled, your settings and saves are copied from
its folder (`DK64Recompiled`) the first time you launch this build. The copy is
one-way and happens once: the old folder is left exactly as it is, so the other
build keeps working, but anything you do from then on — saves, settings, mods —
is written to the `DK64UnKONGtrolled` folder above and will not appear in the old
one. If you want to go back to a save made here, copy it across yourself.

#### How do I choose a different ROM?
**You don't.** This project is a port of one specific game from one specific release: the US N64 version of Donkey Kong 64. It is not an emulator. ROMs in formats other than `.z64` will be automatically converted as long as they are the correct ROM.

---

## Known Issues

* Intel GPUs on Linux may not currently work. If you have Vulkan development experience on Linux, contributions are welcome.
* The prebuilt Linux binary may not work on all distributions. If you encounter this, try building locally, adding the Windows version via Proton, or launching via Gamescope or Steam Linux Runtime as a compatibility layer.
* Overlays such as MSI Afterburner, and software such as Wallpaper Engine, can cause rendering issues. Disabling them is recommended.

---

## Building

Prebuilt binaries (which do not contain game assets) are available in the [Releases](https://github.com/christopher-conley/Donkey-Kong-64-UnKONGtrolled/releases) section. If you'd prefer to build from source, see [BUILDING.md](BUILDING.md).

---

## Contributing

All contributions are welcome. AI-assisted code is explicitly permitted and encouraged — see [CONTRIBUTING.md](CONTRIBUTING.md) for the full philosophy, guidelines, and lore.

---

## Libraries Used and Projects Referenced

* [RT64](https://github.com/rt64/rt64) — rendering engine
* [RmlUi](https://github.com/mikke89/RmlUi) — menus and launcher
* [lunasvg](https://github.com/sammycage/lunasvg) — SVG rendering (used by RmlUi)
* [FreeType](https://freetype.org/) — font rendering (used by RmlUi)
* [moodycamel::ConcurrentQueue](https://github.com/cameron314/concurrentqueue) — lock-free MPMC queues and semaphores
* [Gamepad Motion Helpers](https://github.com/JibbSmart/GamepadMotionHelpers) — sensor fusion and gyro aiming calibration
* [Donkey Kong 64 Decompilation](https://gitlab.com/dk64_decomp/dk64) — headers and function definitions used for patches and enhancements
* [Ares emulator](https://github.com/ares-emulator/ares) — RSP vector instruction reference implementations

Special thanks to [thecozies](https://github.com/thecozies) for designing and helping implement the launcher and config menus.
Special thanks to [fewffwa](https://github.com/fewffwa) for testing and bug reporting.

---

*Forked from [Donkey Kong 64 Rekongpiled](https://github.com/Rainchus/Donkey-Kong-64-Recompiled). Built with spite. Maintained with AI. 🦍*

