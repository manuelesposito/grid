#!/bin/zsh
# Build Vibedesk.app and the vibedesk command. The app is signed with the same certificate every time so macOS keeps its permission.
set -e
APP=~/Applications/Vibedesk.app
cd "${0:A:h}"
swiftc -O Arrange.swift cli/main.swift -o vibedesk
pkill -x Vibedesk || true
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources && cp app/Info.plist $APP/Contents/Info.plist && cp app/Vibedesk.icns $APP/Contents/Resources/Vibedesk.icns
swiftc -O Arrange.swift app/main.swift app/Focus.swift app/Script.swift app/Workspaces.swift app/Terminal.swift app/Picture.swift app/Custom.swift app/Carousel.swift app/Magnet.swift app/Update.swift -D PARKED -o $APP/Contents/MacOS/Vibedesk
codesign -s "Apple Development: Manuel Esposito (K3FWKBL8WS)" --force $APP
open $APP
