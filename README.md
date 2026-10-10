# Grid

A small menu bar tool for the Mac that arranges your windows in tidy rows, with an even space between them.

- **Layouts:** pick one from the menu, or press Control-Option-1 to 9. Control-Option-0 chooses one for you.
- **Half height:** hold Shift, in the menu or on the shortcut, and the same rows sit in a band across the middle of the screen.
- **In the Middle:** one window in a box in the middle (Control-Option-M), seven tenths of the screen each way.
- **Big Left, Big Right:** one big window on one side, all the others stacked on the other (Control-Option-Left and -Right).
- **New versions:** when a newer Grid is out, the menu says so at the top. A click fetches it.
- **Custom:** up to four rows, each with your own number of windows, in a box of full, three quarters or half the screen's width and height.
- **Swap by dragging:** after an arrangement, drop a window on another window's tile and the two swap places. A window set down anywhere else stays where you left it.

## Install

1. Download `Grid.zip` from https://github.com/manuelesposito/grid/releases/latest, unzip it and move `Grid` into your Applications folder.
2. Open it. A small grid icon appears in the menu bar.
3. macOS asks for **Accessibility**. Grid needs it to move and resize windows. Allow it in
   System Settings, Privacy & Security, Accessibility.

Grid runs on macOS 14 or later, on Apple silicon and Intel Macs. To start it with your Mac, choose
Settings, Open at Login in its menu.

Grid works offline. Once a day it asks GitHub for the number of the newest version and says in its menu
when there is one; nothing about you or your Mac is sent. Settings, Look for New Versions switches it off.

The download is signed and checked by Apple, so it opens with a plain double-click.

## Build it yourself

Grid is a handful of Swift files and needs only Xcode's command line tools. `build.sh` builds the app
into `~/Applications` and signs it; put the name of your own signing certificate into the script first.

## License

MIT. Free to use, change and share.
