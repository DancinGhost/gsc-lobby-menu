# gsc-lobby-menu

Server-side / host-side GSC lobby administration menu framework for self-hosted custom servers and private matches (compatible with Plutonium):

- **`t6` MP** (Call of Duty: Black Ops II Multiplayer)
- **`iw5` MP** (Call of Duty: Modern Warfare 3 Multiplayer)

> **Notice:** This is an unofficial, host-side / custom-server GSC scripting project for private matches and self-hosted servers only. No copyrighted game files or assets are included, and this project is not affiliated with Activision Publishing, Inc., Treyarch, Infinity Ward, or the Plutonium Project. See [Legal & Disclaimer](#legal--disclaimer).

> **Targets:** `t6/zm` and `t4` targets are not implemented yet. A new target only needs an entry file with the game hooks (see [Adding a game](#adding-a-game)).

## Quickstart

### Option A: Drop-in download (easiest)

1. Download the ready-to-use `.gsc` file for your game from the [latest Release](https://github.com/DancinGhost/gsc-lobby-menu/releases/latest):
   - **Black Ops II (`t6`)**: `lobbymenu_t6_mp.gsc`
   - **Modern Warfare 3 (`iw5`)**: `lobbymenu_iw5_mp.gsc`
2. Drop it into your Plutonium scripts folder (create `scripts\mp` if needed):
   - **Black Ops II (`t6`)**: `%LOCALAPPDATA%\Plutonium\storage\t6\scripts\mp\`
   - **Modern Warfare 3 (`iw5`)**: `%LOCALAPPDATA%\Plutonium\storage\iw5\scripts\mp\`
3. Start a private match or custom server (or run `map_restart` in the `~` console if already in a match).
4. Once spawned, press **`ADS` + `Melee`** to open the menu. Use **D-Pad** to navigate/adjust, **`Use`** to select, and **`Melee`** to go back/close.

The match host gets `Host` access automatically. On dedicated servers, preset `mm_admins` in your server config (see [Server configuration](#server-configuration)).

### Option B: Build from source

> **Important:** Do **not** copy files from `src/` directly into Plutonium. The files in `src/<game>/mp/` are incomplete entry stubs without `src/common/menu_core.gsc` and will fail with `Unresolved external : "mmcoreinit"` / `"mmgiveweapon"` errors. Always run the build script first and install the assembled file from `build/`.

**Windows (PowerShell):**

```powershell
git clone https://github.com/DancinGhost/gsc-lobby-menu.git
cd gsc-lobby-menu
.\scripts\build.ps1 -InstallToPlutonium
```

*(Pass `-Game t6` or `-Game iw5` to install only one game.)*

**Linux / macOS:**

```bash
git clone https://github.com/DancinGhost/gsc-lobby-menu.git
cd gsc-lobby-menu
./scripts/build.sh --install
```

*(Pass `--storage "/path/to/Plutonium/storage"` if Plutonium is not in your default Wine prefix.)*

## Features

- **Scrolling HUD menu**: rows are allocated once and only their text changes. Distinct strings are counted and freed before the configstring limit is reached ("overflow fix").
- **Access tiers**: `Host`/`Owner`, `Admin`, `VIP`, `None`. You can only manage players below your own level, and only grant levels below your own.
- **Persistent access**: grants are saved by GUID in the `mm_admins` dvar, so they survive fast restarts and map changes. They can also be preset in the server config.
- **Self options**: God Mode, Infinite Ammo, UFO / Noclip, Speed Boost (adjustable multiplier), Third Person, Suicide.
- **Weapon loadouts**: game-specific weapons, Refill All Ammo, Take All Weapons.
- **Lobby settings (Admin+)**: Super Jump, adjustable Gravity, Spawn Bot, Kick All Bots, Fast Restart. Changed dvars are backed up and restored at game end and on the next map load.
- **Player manager (Admin+)**: set or revoke access, freeze, kill, kick, teleport to, bring to you.

Weapons and offhands are disabled while the menu is open, so menu buttons don't knife, reload, or throw. The menu closes automatically on death and at game end. Revoking a player's access also turns off their active mods.

## Controls

| Action | Input |
| :--- | :--- |
| **Open menu** | `ADS` + `Melee` |
| **Scroll up / down** | D-Pad Up / Down (`+actionslot 1` / `+actionslot 2`) |
| **Adjust value** | D-Pad Left / Right (`+actionslot 3` / `+actionslot 4`) |
| **Select** | `Use` |
| **Back / close** | `Melee` |

**UFO mode:** `Attack` flies forward along your view, `ADS` back, `Lethal` up, `Tactical` down. Speed is set by **UFO Speed** in Self Options.

## Project layout

```text
src/
├── common/
│   └── menu_core.gsc          # shared engine: input, navigation, HUD, toggles, access, actions
├── t6/mp/lobbymenu_t6_mp.gsc    # T6 entry: includes, init(), game hooks, weapon list
└── iw5/mp/lobbymenu_iw5_mp.gsc  # IW5 entry: includes, init(), game hooks, weapon list
scripts/
├── build.sh                   # Linux/macOS build / compile / install
└── build.ps1                  # Windows build / compile / install
.github/workflows/build.yml    # CI: validates builds on push/PR and publishes Releases on v* tags
```

The entry files are **not** loadable on their own. The build appends `src/common/*.gsc` to each entry file and writes one self-contained script per game to `build/<game>/mp/lobbymenu_<game>_mp.gsc`.

## Building & installing

Plutonium loads GSC source directly, so a plain build only assembles the files. `--compile` / `-Compile` also runs **[xensik/gsc-tool](https://github.com/xensik/gsc-tool/releases)** to catch errors before you launch the game.

### Windows (PowerShell)

```powershell
# Assemble both games into .\build\
.\scripts\build.ps1

# Assemble and copy into %LOCALAPPDATA%\Plutonium\storage\<game>\scripts\mp\
.\scripts\build.ps1 -InstallToPlutonium

# Also validate/compile with gsc-tool (pass -Iw5IncludeDir if you want full IW5 bytecode compilation)
.\scripts\build.ps1 -Compile
```

### Linux / macOS

```bash
./scripts/build.sh                      # assemble both games
./scripts/build.sh t6 --install         # install into $PLUTONIUM_STORAGE or the default Wine prefix
./scripts/build.sh --storage "/path/to/Plutonium/storage"   # explicit storage folder (implies --install)
GSC_TOOL=/path/to/gsc-tool ./scripts/build.sh --compile
```

T6 compiles standalone without external include files. For IW5, `--compile` runs a syntax check (`parse` mode) by default, which is all you need because Plutonium loads the assembled `.gsc` source file directly. If you also want full IW5 bytecode compilation locally, point `IW5_INCLUDE_DIR` / `-Iw5IncludeDir` at your own local IW5 script includes directory.

### Manual install

After running `.\scripts\build.ps1` or `./scripts/build.sh`, copy the assembled script from `build/` (not `src/`):

- **Black Ops II (`t6`)**: `build/t6/mp/lobbymenu_t6_mp.gsc` → `%LOCALAPPDATA%\Plutonium\storage\t6\scripts\mp\`
- **Modern Warfare 3 (`iw5`)**: `build/iw5/mp/lobbymenu_iw5_mp.gsc` → `%LOCALAPPDATA%\Plutonium\storage\iw5\scripts\mp\`

In-game, run `map_restart` in the console (`~`) to reload scripts.

### Publishing a release

Pushing a version tag matching `v*` triggers GitHub Actions to assemble, validate with `gsc-tool`, and publish a GitHub Release with `lobbymenu_t6_mp.gsc`, `lobbymenu_iw5_mp.gsc`, and `SHA256SUMS.txt` attached:

```bash
git tag v0.1.0
git push origin v0.1.0
```

## Server configuration

| Dvar | Purpose |
| :--- | :--- |
| `mm_admins` | Comma-separated `guid:level` list (`1` VIP, `2` Admin, `3` Owner). Updated automatically when access is granted in-game. Preset it in your server config to give owners access on dedicated servers, where nobody is the host, e.g. `set mm_admins "123456:3,789012:2"`. |
| `mm_orig_<dvar>` | Internal backups of dvars changed by the lobby settings. Leave these alone. |

## Adding a game

Create `src/<game>/<mode>/lobbymenu_<game>_<mode>.gsc` with the game's `#include` lines and an `init()` that sets `level.menuTitle`, `level.menuDirectionIsPolled` and `level.menuGravityDvar`, then calls `mmCoreInit()`. Then define these hooks:

| Hook | Purpose |
| :--- | :--- |
| `game_onPlayerConnect()` | Per-player setup at connect (e.g. `notifyOnPlayerCommand` binds) |
| `game_readDirection()` | Returns `"up"`, `"down"`, `"left"`, `"right"` or `undefined` |
| `game_setThirdPerson(enabled)` | Game-specific third-person switch |
| `game_addWeaponOptions(menuId)` | Adds weapon entries with `mmAddOption()` |
| `game_spawnBot()` | Adds a bot that joins a team; returns `true` on success |

Then add the target to the build scripts and the CI workflow.

## Legal & Disclaimer

- **Scope & intended use:** This project consists solely of host-side / server-side GSC scripts intended for private matches and self-hosted custom servers. It does not modify game executables, inject into memory, bypass anti-cheat or DRM, or operate on official public matchmaking servers.
- **No game assets included:** This repository contains only original script source code and build helpers. It does not include, host, or distribute any game binaries, assets, or copyrighted game scripts. A legitimately owned copy of each supported game is required.
- **Trademarks & non-affiliation:** This is an independent, unofficial community project and is not affiliated with, endorsed by, or sponsored by Activision Publishing, Inc., Treyarch, Infinity Ward, or the Plutonium Project. All game titles, weapon names, and trademarks mentioned for compatibility purposes are the property of their respective owners.
- **Third-party tools:** Optional syntax checking / compilation invokes [xensik/gsc-tool](https://github.com/xensik/gsc-tool) (licensed separately under GPL-3.0), which is neither bundled nor redistributed by this repository.
- **License & warranty:** This repository's original source code is released under the [MIT License](LICENSE) and provided "AS IS", without warranty of any kind.
