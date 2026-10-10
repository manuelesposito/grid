#!/bin/zsh
# Builds the Vibedesk that is given to other people, as dist/Vibedesk.zip: for Apple silicon and Intel Macs,
# signed with the Developer ID and checked by Apple, so it opens with a plain double-click.
# Needs once: a "Developer ID Application" certificate in the keychain, and
#   xcrun notarytool store-credentials grid-notary --apple-id <Apple ID> --team-id B4DF35G839
# build.sh stays the way to build the Vibedesk on this Mac: it keeps its permission.
set -e
cd "${0:A:h}"
# The version number goes into the app, so Vibedesk can tell a newer release from its own.
VERSION=$1
[[ -z $VERSION ]] && { echo "Usage: ./release.sh 1.3   (then: gh release create v1.3 dist/Vibedesk.zip ...)"; exit 1 }
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" app/Info.plist
APP=dist/Vibedesk.app
rm -rf dist && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
# Only what Vibedesk does ships: Focus, Workspaces and the filming harness are parked (build.sh, -D PARKED).
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos14.0 Arrange.swift app/main.swift app/Custom.swift app/Magnet.swift app/Update.swift -o dist/Vibedesk-$arch
done
lipo -create dist/Vibedesk-arm64 dist/Vibedesk-x86_64 -output $APP/Contents/MacOS/Vibedesk && rm dist/Vibedesk-arm64 dist/Vibedesk-x86_64
cp app/Info.plist $APP/Contents/Info.plist && cp app/Vibedesk.icns $APP/Contents/Resources/Vibedesk.icns
codesign --force --options runtime --timestamp --entitlements app/Vibedesk.entitlements -s "Developer ID Application" $APP
ditto -c -k --keepParent $APP dist/Vibedesk.zip
xcrun notarytool submit dist/Vibedesk.zip --keychain-profile grid-notary --wait
# The proof of Apple's check travels inside the app, so it opens without a connection too.
xcrun stapler staple $APP
rm dist/Vibedesk.zip && ditto -c -k --keepParent $APP dist/Vibedesk.zip
spctl -a -vv $APP
echo "Ready: dist/Vibedesk.zip"
