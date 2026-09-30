#!/bin/zsh
# Builds the Grid that is given to other people, as dist/Grid.zip: for Apple silicon and Intel Macs,
# signed with the Developer ID and checked by Apple, so it opens with a plain double-click.
# Needs once: a "Developer ID Application" certificate in the keychain, and
#   xcrun notarytool store-credentials grid-notary --apple-id <Apple ID> --team-id B4DF35G839
# build.sh stays the way to build the Grid on this Mac: it keeps its permission.
set -e
cd "${0:A:h}"
APP=dist/Grid.app
rm -rf dist && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
for arch in arm64 x86_64; do
  swiftc -O -target $arch-apple-macos14.0 Arrange.swift app/*.swift -o dist/Grid-$arch
done
lipo -create dist/Grid-arm64 dist/Grid-x86_64 -output $APP/Contents/MacOS/Grid && rm dist/Grid-arm64 dist/Grid-x86_64
cp app/Info.plist $APP/Contents/Info.plist && cp app/Grid.icns $APP/Contents/Resources/Grid.icns
codesign --force --options runtime --timestamp --entitlements app/Grid.entitlements -s "Developer ID Application" $APP
ditto -c -k --keepParent $APP dist/Grid.zip
xcrun notarytool submit dist/Grid.zip --keychain-profile grid-notary --wait
# The proof of Apple's check travels inside the app, so it opens without a connection too.
xcrun stapler staple $APP
rm dist/Grid.zip && ditto -c -k --keepParent $APP dist/Grid.zip
spctl -a -vv $APP
echo "Ready: dist/Grid.zip"
