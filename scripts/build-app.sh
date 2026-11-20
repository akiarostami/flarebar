#!/bin/bash
# Builds Flarebar and installs it as ~/Applications/Flarebar.app.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="${FLAREBAR_APP:-$HOME/Applications/Flarebar.app}"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Flarebar"

# Replace a running copy.
osascript -e 'tell application id "com.minorkey.flarebar" to quit' >/dev/null 2>&1 || true

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$BIN" "$APP/Contents/MacOS/Flarebar"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Flarebar</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>com.minorkey.flarebar</string>
    <key>CFBundleName</key><string>Flarebar</string>
    <key>CFBundleDisplayName</key><string>Flarebar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.2</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>Personal tool.</string>
</dict>
</plist>
PLIST
# Sign with FLAREBAR_SIGN_IDENTITY if set, else the first code-signing certificate in the
# Keychain, else ad hoc ("-"). A real certificate gives the app a stable identity, so macOS
# permissions such as Keychain access survive rebuilds.
IDENTITY="${FLAREBAR_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' 'NF>=3 {print $2; exit}')}"
IDENTITY="${IDENTITY:--}"
if [[ "$IDENTITY" == "Developer ID Application"* ]]; then
    # What Apple's notary service requires of apps given to other people.
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
    codesign --force --sign "$IDENTITY" "$APP"
fi
if [ "$IDENTITY" = "-" ]; then echo "Signed ad hoc (no certificate found)"; else echo "Signed with: $IDENTITY"; fi

# An ad hoc signature changes with every build, and the Keychain item's access list names
# the app by its signature, so re-create the item for the new build. With a real certificate
# the app's identity is stable and the app owns its item; leave it alone.
if [ "$IDENTITY" = "-" ] && TOKENS="$(security find-generic-password -s flarebar -a token -w 2>/dev/null)" && [ -n "$TOKENS" ]; then
    security delete-generic-password -s flarebar -a token >/dev/null 2>&1 || true
    # Passed on stdin, so the tokens never appear in a process list.
    printf 'add-generic-password -U -s flarebar -a token -T "%s" -T /usr/bin/security -w "%s"\n' "$APP" "$TOKENS" \
        | security -i >/dev/null
fi
echo "Installed $APP"
