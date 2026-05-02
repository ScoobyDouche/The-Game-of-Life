#!/usr/bin/env bash
# ============================================================================
# The Game of Life (Hasbro Interactive, 1998) — automated installer for Linux
# Target: Linux Mint / Ubuntu / Debian, x86_64
#
# Reads directly from the mounted CD. Skips InstallShield's setup.exe — the
# Life\ folder on the disc already contains the fully-extracted game, so
# there's nothing to unpack. Copies the game into a dedicated 32-bit Wine
# prefix, sets up a permanent fake CD-ROM drive (volume label GameOfLife)
# so the disc isn't needed at runtime, writes a launcher and menu entry,
# then launches.
#
# Usage:
#   ./install-game-of-life.sh             # auto-detect mounted disc
#   ./install-game-of-life.sh -y          # auto-detect, no prompts
#   ./install-game-of-life.sh -s /media/USER/GameOfLife   # explicit
# ============================================================================

set -euo pipefail

# ----- config ---------------------------------------------------------------
PREFIX="${GOL_PREFIX:-$HOME/.local/share/wineprefixes/game-of-life}"
INSTALL_REL="drive_c/Program Files/Hasbro Interactive/Game of Life"
INSTALL_DIR="$PREFIX/$INSTALL_REL"
FAKE_CD="$PREFIX/fake-cd"
DOSDEV="$PREFIX/dosdevices"
LAUNCHER="$HOME/.local/bin/game-of-life"
DESKTOP_FILE="$HOME/.local/share/applications/game-of-life.desktop"
VOLUME_LABEL="GameOfLife"

SRC=""
ASSUME_YES=0

while getopts ":ys:h" opt; do
  case "$opt" in
    y) ASSUME_YES=1 ;;
    s) SRC="$OPTARG" ;;
    h) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "Unknown option. Try -h." >&2; exit 2 ;;
  esac
done

# ----- helpers --------------------------------------------------------------
msg()  { printf '\033[1;36m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[X]\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
  (( ASSUME_YES )) && return 0
  local ans
  read -rp "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

find_ci_path() {
  local base="$1" rel="$2"
  local current="$base"
  local seg hit
  local -a segments
  IFS='/' read -ra segments <<<"$rel"
  for seg in "${segments[@]}"; do
    [[ -z "$seg" ]] && continue
    hit="$(find "$current" -maxdepth 1 -mindepth 1 -iname "$seg" -print -quit 2>/dev/null)"
    [[ -n "$hit" ]] || return 1
    current="$hit"
  done
  printf '%s\n' "$current"
}

is_gol_disc() {
  local d="$1"
  [[ -d "$d" ]] || return 1
  find_ci_path "$d" "Life/life.exe" >/dev/null || return 1
  find_ci_path "$d" "DISK1.ID"      >/dev/null || return 1
  return 0
}

# ----- 1. locate the disc --------------------------------------------------
if [[ -z "$SRC" ]]; then
  msg "Looking for a mounted Game of Life disc..."
  for base in "/media/$USER" "/run/media/$USER" /media /mnt; do
    [[ -d "$base" ]] || continue
    while IFS= read -r -d '' d; do
      if is_gol_disc "$d"; then
        SRC="$d"
        break 2
      fi
    done < <(find "$base" -mindepth 1 -maxdepth 2 -type d -print0 2>/dev/null)
  done
  [[ -n "$SRC" ]] || die "Couldn't auto-find the disc. Pass it explicitly:
  $0 -y -s /media/$USER/GameOfLife"
fi

is_gol_disc "$SRC" || die "Doesn't look like the Game of Life disc: $SRC
(needs Life/life.exe and DISK1.ID at the root)"

ok "Disc found: $SRC"
LIFE_DIR="$(find_ci_path "$SRC" "Life")"

# ----- 2. install host packages --------------------------------------------
need=()
command -v wine >/dev/null 2>&1 || need+=(wine)
if [[ "$(uname -m)" == "x86_64" ]]; then
  if ! dpkg -s wine32 >/dev/null 2>&1 && ! dpkg -s wine32:i386 >/dev/null 2>&1; then
    need+=(wine32)
  fi
fi

if (( ${#need[@]} )); then
  msg "Need to install: ${need[*]}"
  if confirm "Run sudo apt to install these now?"; then
    sudo dpkg --add-architecture i386 >/dev/null 2>&1 || true
    sudo apt-get update
    for p in "${need[@]}"; do
      if [[ "$p" == "wine32" ]]; then
        sudo apt-get install -y wine32:i386 || sudo apt-get install -y wine32 || \
          warn "wine32 install failed — game will only work if Wine has 32-bit support already."
      else
        sudo apt-get install -y "$p"
      fi
    done
  else
    die "Cannot continue without required packages."
  fi
fi
ok "Host packages ready."

# ----- 3. create the Wine prefix -------------------------------------------
if [[ -d "$PREFIX" ]]; then
  warn "Existing prefix found at $PREFIX"
  if confirm "Wipe it and start fresh?"; then
    rm -rf "$PREFIX"
  else
    die "Aborted by user."
  fi
fi

msg "Creating 32-bit Wine prefix at $PREFIX"
export WINEPREFIX="$PREFIX"
export WINEARCH=win32
export WINEDLLOVERRIDES="mscoree=;mshtml="   # silence Mono / Gecko prompts
export WINEDEBUG=-all
mkdir -p "$(dirname "$PREFIX")"
wineboot --init >/dev/null 2>&1
ok "Prefix initialised."

msg "Setting Windows version → Windows 98"
wine reg add 'HKCU\Software\Wine' /v Version /t REG_SZ /d win98 /f >/dev/null 2>&1 || \
  warn "Could not set Wine version (non-fatal)."

# ----- 4. copy the game into the install dir ------------------------------
msg "Copying game files into the prefix (~440 MB — slow from CD, be patient)"
mkdir -p "$INSTALL_DIR"
cp -r "$LIFE_DIR"/. "$INSTALL_DIR"/
# CD files are read-only; clear that so the prefix is writable for saves and
# so an uninstall can actually remove the directory tree.
chmod -R u+rwX "$INSTALL_DIR"
ok "Game files installed."

# ----- 5. registry entries (Hasbro convention) -----------------------------
msg "Writing registry keys"
RKEY='HKLM\Software\Hasbro Interactive\Game of Life\Setup'
WPATH='C:\Program Files\Hasbro Interactive\Game of Life'
wine reg add "$RKEY" /v Path    /t REG_SZ /d "$WPATH" /f >/dev/null 2>&1
wine reg add "$RKEY" /v Version /t REG_SZ /d "1.0"    /f >/dev/null 2>&1
ok "Registry keys written."

# ----- 6. build the fake CD (so the disc isn't needed at runtime) ---------
msg "Building permanent fake CD at $FAKE_CD"
rm -rf "$FAKE_CD"
mkdir -p "$FAKE_CD"

# Mirror everything from the disc EXCEPT the giant Life/ folder — we recreate
# that with symlinks back to the install dir to save ~440 MB of disk.
shopt -s dotglob nullglob
for entry in "$SRC"/*; do
  name="$(basename "$entry")"
  [[ "${name,,}" == "life" ]] && continue
  cp -r "$entry" "$FAKE_CD/"
done
shopt -u dotglob nullglob

# Same chmod treatment for the fake CD — the small files copied off the disc
# come over read-only too.
chmod -R u+rwX "$FAKE_CD"

# Recreate Life/ as symlinks pointing at the already-installed files.
# This way the CD-side path "D:\Life\life.exe" resolves, but uses zero extra
# disk because the data files are stored once.
mkdir -p "$FAKE_CD/Life"
shopt -s dotglob nullglob
for f in "$INSTALL_DIR"/*; do
  ln -sf "$f" "$FAKE_CD/Life/$(basename "$f")"
done
shopt -u dotglob nullglob

# Volume label — Wine reads this file as the drive label
echo -n "$VOLUME_LABEL" > "$FAKE_CD/.windows-label"
ok "Fake CD built (label: $VOLUME_LABEL)"

# ----- 7. wire up Wine drive D: as a CD-ROM --------------------------------
msg "Mapping Wine drive D: → fake CD (type: cdrom)"
mkdir -p "$DOSDEV"
rm -f "$DOSDEV/d:" "$DOSDEV/d::"
ln -s "$FAKE_CD" "$DOSDEV/d:"
wine reg add 'HKLM\Software\Wine\Drives' /v "D:" /t REG_SZ /d "cdrom" /f >/dev/null 2>&1 || \
  warn "Couldn't register D: as cdrom (non-fatal — game may still work)."
ok "Drive D: registered as CD-ROM."

# ----- 8. launcher + desktop entry -----------------------------------------
mkdir -p "$(dirname "$LAUNCHER")" "$(dirname "$DESKTOP_FILE")"

cat > "$LAUNCHER" <<EOF
#!/usr/bin/env bash
# Auto-generated launcher for The Game of Life
# Runs inside a Wine virtual desktop so the game can't change the real
# screen resolution (which causes the desktop to get stuck at 800x600
# if the game crashes or quits without restoring it).
export WINEPREFIX="$PREFIX"
export WINEARCH=win32
export WINEDEBUG=-all
cd "$INSTALL_DIR"
exec wine explorer /desktop=life,800x600 life.exe "\$@"
EOF
chmod +x "$LAUNCHER"

cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=The Game of Life
Comment=Hasbro Interactive (1998) — via Wine
Exec=$LAUNCHER
Categories=Game;
Terminal=false
EOF

update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

ok "Launcher script:  $LAUNCHER"
ok "Menu entry:       $DESKTOP_FILE"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) : ;;
  *) warn "$HOME/.local/bin is not on your PATH — add it to ~/.bashrc to launch by name." ;;
esac

# ----- 9. launch -----------------------------------------------------------
echo
ok "Install complete. The disc is no longer needed."
msg "Launching the game..."
echo
exec "$LAUNCHER"
