#!/bin/zsh
# Build Grid.app and the grid command. The app is signed with the same certificate every time so macOS keeps its permission.
set -e
APP=~/Applications/Grid.app
cd "${0:A:h}"
swiftc -O Arrange.swift cli/main.swift -o grid
pkill -x Grid || true
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources && cp app/Info.plist $APP/Contents/Info.plist && cp app/Grid.icns $APP/Contents/Resources/Grid.icns
swiftc -O Arrange.swift app/main.swift app/Focus.swift app/Script.swift app/Workspaces.swift app/Terminal.swift app/Picture.swift app/Custom.swift -o $APP/Contents/MacOS/Grid
codesign -s "Apple Development: Manuel Esposito (K3FWKBL8WS)" --force $APP
open $APP
