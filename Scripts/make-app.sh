#!/usr/bin/env bash
#
# Builds Piper.app: compiles the Swift executable in release mode and
# assembles a proper .app bundle including the embedded CPython runtime.
#
# Prerequisite: run Scripts/bundle-runtime.sh first so ./Runtime exists.
#
# Env overrides:
#   CODESIGN_IDENTITY   Developer ID (or stable self-signed) identity for
#                       signing. Defaults to ad-hoc ("-") for local use. Use a
#                       stable self-signed identity ("nicx Selfsign") so macOS
#                       keeps login-item and notification grants across rebuilds.
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME="$ROOT/Runtime"
APP="$ROOT/dist/Piper.app"
IDENTITY="${CODESIGN_IDENTITY:--}"
ENTITLEMENTS="$ROOT/Resources/Piper.entitlements"

# Läuft die App aus genau diesem dist/, würde der Build ihr das Bundle unter den Füßen
# weglöschen: der Prozess liefe mit ALTEM Code aus einem gelöschten Bundle weiter, macOS
# graut ihn aus, das Menü reagiert nicht mehr — beenden ginge nur noch per `kill`. Bei
# dieser App stoppt ein sauberer Quit zusätzlich den wyoming-piper-Kindprozess.
# Aus /Applications gestartete Instanzen sind unkritisch.
RUNNING="$(pgrep -f "$APP/Contents/MacOS/Piper" || true)"
if [[ -n "$RUNNING" ]]; then
  echo "ABBRUCH: Piper läuft gerade aus $ROOT/dist (PID: ${RUNNING//$'\n'/ })." >&2
  echo "         Der Build würde das laufende Bundle löschen." >&2
  echo "         Erst die App beenden (Menüleiste -> Beenden), dann erneut bauen." >&2
  exit 1
fi

if [[ ! -x "$RUNTIME/python/bin/python3" ]]; then
  echo "error: $RUNTIME/python not found — run Scripts/bundle-runtime.sh first." >&2
  exit 1
fi

# SDK explizit auf die stabile macOS-26-Reihe pinnen. Ein macOS-27-Beta-SDK
# hat sich als Default eingenistet (Symlink MacOSX.sdk -> MacOSX27.0.sdk);
# dessen SwiftUI-Makro-Plugin fehlt, `swift build` bricht dann mit
# "SwiftUIMacros.StateMacro could not be found" ab (Fix aus ha-screentime).
CLT_SDKS="/Library/Developer/CommandLineTools/SDKs"
if [[ -d "$CLT_SDKS/MacOSX26.sdk" ]]; then
  export SDKROOT="$CLT_SDKS/MacOSX26.sdk"
  echo "==> SDKROOT gepinnt: $(readlink -f "$SDKROOT" 2>/dev/null || echo "$SDKROOT")"
fi

echo "==> Building release executable"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/Piper"

echo "==> Assembling app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/Piper"
cp -R "$RUNTIME" "$APP/Contents/Resources/Runtime"
[[ -f "$ROOT/Resources/AppIcon.icns" ]] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"

echo "==> Code signing (identity: $IDENTITY)"
# Sign inside-out: every Mach-O file inside the embedded CPython runtime first,
# then the Swift binary, then the bundle. The interpreter and its C-extension
# .so/.dylib files must each carry the JIT / library-validation entitlements,
# otherwise the hardened runtime refuses to load them.
RUNTIME_IN_APP="$APP/Contents/Resources/Runtime/python"

sign() {
  codesign --force --options runtime --timestamp=none \
    --entitlements "$ENTITLEMENTS" -s "$IDENTITY" "$1"
}

echo "    signing Mach-O files in embedded runtime…"
# Find Mach-O binaries (executables + shared libraries) and sign each.
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q 'Mach-O'; then
    sign "$f"
  fi
done < <(find "$RUNTIME_IN_APP" -type f \( -name '*.so' -o -name '*.dylib' -o -perm -u+x \) -print0)

# Ensure the interpreter symlink target itself is signed.
sign "$RUNTIME_IN_APP/bin/python3"

echo "    signing app executable…"
sign "$APP/Contents/MacOS/Piper"

echo "    signing bundle…"
sign "$APP"

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP" || true

echo "==> Done: $APP"
echo "    Run with: open \"$APP\"   (look for the waveform icon in the menu bar)"
