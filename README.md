# The Game of Life — Linux installer

Automated installer for *The Game of Life* (Hasbro Interactive, 1998) on Linux Mint, Ubuntu, and Debian via Wine. The disc already ships the game pre-extracted, so the script just copies it into a dedicated 32-bit Wine prefix, writes the registry keys the game expects, and builds a fake CD-ROM drive so the disc is never needed again. One command from disc to playable.

## What's in here

A single script, `install-game-of-life.sh`. Run it once with the disc inserted and it handles the whole pipeline from dependency install through launching the game — including the fake-CD setup so the disc is never needed afterwards.

## Requirements

A 64-bit Linux Mint, Ubuntu, or Debian system with `sudo` access. The first run will install `wine` and `wine32:i386` if either is missing, enabling the `i386` foreign architecture along the way. You also need the original *Game of Life* CD inserted — on a default Mint desktop this auto-mounts at `/media/$USER/GameOfLife`. The disc is needed only during install; once the script finishes you can eject it and never need it again.

## Usage

Insert the disc and let it auto-mount, then from the directory containing the script:

```bash
chmod +x install-game-of-life.sh
./install-game-of-life.sh -y
```

The `-y` flag skips all confirmation prompts. The game launches as soon as the install finishes. Future launches: run `game-of-life` from a terminal, or click "The Game of Life" in your application menu.

If the auto-detect can't find the disc, pass it explicitly:

```bash
./install-game-of-life.sh -y -s /media/$USER/GameOfLife
```

## Under the hood

The script scans `/media/$USER/`, `/run/media/$USER/`, `/media/`, and `/mnt/` for a directory containing `Life/life.exe` and `DISK1.ID`. Filename matching is case-insensitive, so it works whether the mount exposes uppercase (typical for ISO9660) or lowercase names. Once it locates the disc, it installs `wine` and `wine32:i386` if needed, then creates a fresh 32-bit Wine prefix at `~/.local/share/wineprefixes/game-of-life` and sets the reported Windows version to Win98.

Unlike most InstallShield-era games, the disc ships with the game already fully extracted in a `Life/` directory — no archive to crack open. The script just copies that folder's contents (about 440 MB of `life.exe` plus `.BLT` data files) into the prefix at `<prefix>/drive_c/Program Files/Hasbro Interactive/Game of Life/`. Two values get written under `HKLM\Software\Hasbro Interactive\Game of Life\Setup` so anything in the game that consults the registry for its install path finds the right answer.

The original release does a runtime CD-presence check, so the script also builds a permanent "fake CD" at `<prefix>/fake-cd` that mirrors the disc's directory layout — small files like `AutoRun.exe`, `DISK1.ID`, `SETUP.INI`, and the `DirectX/` folder are copied verbatim, and the `Life/` subfolder is recreated as a tree of symlinks back to the install dir to save 440 MB of duplicated disk. A `.windows-label` file is written containing `GameOfLife` so Wine reports the correct volume label. The fake-cd folder is symlinked into Wine's `dosdevices/` as drive D:, and a registry value under `HKLM\Software\Wine\Drives` registers it as type `cdrom`. From the game's perspective, the disc is permanently in the drive.

Finally, a launcher script lands at `~/.local/bin/game-of-life` (it `cd`s into the install dir and runs `wine life.exe`) and a `.desktop` entry in `~/.local/share/applications/` so the game appears in your application menu under Games.

## File locations

Everything lives under your home directory. The Wine prefix is `~/.local/share/wineprefixes/game-of-life/`, with the game installed at `<prefix>/drive_c/Program Files/Hasbro Interactive/Game of Life/` and the fake CD at `<prefix>/fake-cd/`. The launcher script is `~/.local/bin/game-of-life` and the desktop menu entry is `~/.local/share/applications/game-of-life.desktop`. Set `GOL_PREFIX` in the environment before running the script if you want a different prefix path.

## Troubleshooting

The launcher runs the game inside a Wine virtual desktop by default — the game thinks it owns an 800×600 screen, but Wine confines that to a window so your real desktop resolution is never touched. This avoids a common failure mode where the game changes your actual screen mode on launch and fails to restore it on quit, leaving your desktop stuck at 800×600.

If you'd prefer the game to take over the full screen the way it would on Windows, edit `~/.local/bin/game-of-life` and replace the final `exec` line with:

```bash
exec wine life.exe "$@"
```

Just be aware that if the game crashes you may end up needing to fix your display resolution manually afterwards.

If the game complains about the CD even with the fake-CD setup in place, your disc pressing may use a different volume label than `GameOfLife`. Check what your mount is called (`ls /media/$USER/`) and edit the `VOLUME_LABEL=` variable near the top of the script before re-running.

To start over from scratch, wipe the prefix and re-run the installer with the disc inserted:

```bash
rm -rf ~/.local/share/wineprefixes/game-of-life
./install-game-of-life.sh -y
```

## Uninstall

Remove the prefix, the launcher, and the menu entry. The `chmod` step is needed because some files copied off the CD inherit its read-only mode, which blocks `rm -rf` from removing the directory tree:

```bash
chmod -R u+w ~/.local/share/wineprefixes/game-of-life
rm -rf ~/.local/share/wineprefixes/game-of-life
rm -f ~/.local/bin/game-of-life
rm -f ~/.local/share/applications/game-of-life.desktop
update-desktop-database ~/.local/share/applications 2>/dev/null
```

## Notes

The script assumes you own the original CD. Nothing here patches the game binary; the no-CD setup works by exposing a synthetic Wine drive that satisfies the runtime CD-presence check. Wine version requirements are loose — anything from the last several years should work.
