# Grid

A small menu bar tool for the Mac that arranges your windows in tidy rows, with an even space between them.

- **Layouts:** pick one from the menu, or press Control-Option-1 to 9. Control-Option-0 chooses one for you.
- **Coding:** the browser on the left, terminals stacked on the right (Control-Option-C).
- **Custom:** up to four rows, each with your own number of windows.
- **Focus:** the front window moves to the middle and everything behind it goes dark (Control-Option-F).
  Switch to another window and Focus follows.
- **Workspaces:** save the windows on the screen and open them again later.
- **Undo:** Control-Option-Z puts the windows back.

## Install

1. Download `Grid.zip` from https://github.com/manuelesposito/grid/releases/latest, unzip it and move `Grid` into your Applications folder.
2. Open it. A small grid icon appears in the menu bar.
3. macOS asks for **Accessibility**. Grid needs it to move and resize windows. Allow it in
   System Settings, Privacy & Security, Accessibility.

Grid runs on macOS 14 or later, on Apple silicon and Intel Macs. To start it with your Mac, choose
Settings, Open at Login in its menu.

## Two extras for terminal users

- **Bigger text in Focus.** With the Ghostty terminal and a Focus Zoom above 1 ×, the text grows with
  the window. macOS then asks for Screen Recording and for permission to control Ghostty. Grid uses the
  first only for a picture of that one window during the animation; nothing is stored or sent.
- **Waiting windows.** Claude Code windows that have finished get a coloured edge.

Grid works offline and sends nothing anywhere.

The download is signed and checked by Apple, so it opens with a plain double-click.

## Build it yourself

Grid is a handful of Swift files and needs only Xcode's command line tools. `build.sh` builds the app
into `~/Applications` and signs it; put the name of your own signing certificate into the script first.

## License

MIT. Free to use, change and share.
