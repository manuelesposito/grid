#!/bin/zsh
# Builds the SnugGrid that is given to other people, as dist/SnugGrid.zip: for Apple silicon and Intel Macs,
# signed with the Developer ID and checked by Apple, so it opens with a plain double-click.
# Needs once: a "Developer ID Application" certificate in the keychain, and
#   xcrun notarytool store-credentials grid-notary --apple-id <Apple ID> --team-id B4DF35G839
# build.sh stays the way to build the SnugGrid on this Mac: it keeps its permission.
set -e
cd "${0:A:h}"
# One command does the whole release: ./release.sh 1.4
# It writes the version into the app, builds, signs, has Apple check it, commits the version,
# publishes the release on GitHub with the notes from notes.md, and pushes.
VERSION=$1
[[ -z $VERSION ]] && { echo "Usage: ./release.sh 1.4   (notes come from notes.md)"; exit 1 }
[[ -f notes.md ]] || { echo "Write the release notes into notes.md first."; exit 1 }
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" app/Info.plist
APP=dist/SnugGrid.app
rm -rf dist && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
# Only what SnugGrid does ships: Focus, Workspaces and the filming harness are parked (build.sh, -D PARKED).
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos14.0 Arrange.swift app/main.swift app/Custom.swift app/Magnet.swift app/Update.swift -o dist/SnugGrid-$arch
done
lipo -create dist/SnugGrid-arm64 dist/SnugGrid-x86_64 -output $APP/Contents/MacOS/SnugGrid && rm dist/SnugGrid-arm64 dist/SnugGrid-x86_64
cp app/Info.plist $APP/Contents/Info.plist && cp app/SnugGrid.icns $APP/Contents/Resources/SnugGrid.icns
codesign --force --options runtime --timestamp --entitlements app/SnugGrid.entitlements -s "Developer ID Application" $APP
ditto -c -k --keepParent $APP dist/SnugGrid.zip
xcrun notarytool submit dist/SnugGrid.zip --keychain-profile grid-notary --wait
# The proof of Apple's check travels inside the app, so it opens without a connection too.
xcrun stapler staple $APP
rm dist/SnugGrid.zip && ditto -c -k --keepParent $APP dist/SnugGrid.zip
spctl -a -vv $APP
git commit -qm "Version $VERSION" app/Info.plist notes.md || true
gh release create v$VERSION dist/SnugGrid.zip --title "SnugGrid $VERSION" --notes-file notes.md
git push
echo "Released SnugGrid $VERSION."
