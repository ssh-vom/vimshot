# Vimshot

A small macOS screenshot utility with Vim-style keyboard region selection. It uses Apple's native `/usr/sbin/screencapture` engine for the final capture, then copies the PNG to the clipboard and saves it in `~/Pictures/Screenshots`.

## Build and run

```sh
cd ~/projects/vimshot
./build-app.sh
open Vimshot.app
```

Vimshot now stays in the macOS menu bar. Its default global shortcut is **⌥⇧S**. Click the camera icon in the menu bar to take a screenshot or choose **Set Keyboard Shortcut…** to record a new shortcut by pressing it once.

For it to always be available, add `Vimshot.app` to **System Settings → General → Login Items**.

The first use of `e` may ask for macOS Accessibility permission. `w` does not require Accessibility permission.

## Keys

| Key | Action |
|---|---|
| `h`/`j`/`k`/`l`, arrows | Move the crosshair by 10 pixels |
| `20j`, `10l` | Move exactly 20 or 10 pixels (number row or numpad) |
| `H`/`J`/`K`/`L` | Jump to the left/bottom/top/right screen edge |
| `gh`/`gj`/`gk`/`gl` | Alternate directional edge jumps |
| `Ctrl` + movement | Fine movement (1 pixel) |
| `Option` + movement | Fast movement (100 pixels) |
| `g1` … `g9` | Jump to a 3×3 screen grid (`g5` is center) |
| `gg` / `G` | Jump to top-left / bottom-right |
| `0` / `$` | Jump to left / right edge |
| `m` | Jump to center |
| `o` | Swap the active selection corner |
| `Enter` | Set the first corner, then capture |
| `w` | Snap to the window beneath the crosshair |
| `e` | Snap to the Accessibility UI element beneath the crosshair |
| `r` | Reset |
| `Esc` / `q` | Cancel |

The screenshot is saved automatically and copied to the clipboard after capture.
