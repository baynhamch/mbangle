# mbangle

Stealth lid-angle alignment tool for showcase MacBooks.

The app is invisible: no Dock tile, no menu bar item, no window. Press the hotkey
and a small floating readout appears showing the current lid angle against your
saved target; press it again (or Esc) and it is gone.

## Usage

| Key | Action |
| --- | --- |
| `⌃⌥⇧L` | Show / hide the readout (works from any app, any Space, over full-screen) |
| `C` | Set the current angle as the target |
| `↑` / `↓` | Adjust target by 0.1° |
| `⇧↑` / `⇧↓` | Adjust target by 1.0° |
| `Esc` | Hide |
| `⌘Q` | Quit |

The readout shows how far off you are and which way to move the lid — `▲ open 1.6°`
or `▼ close 0.4°` — and turns green reading `ON TARGET` once you are within
tolerance. It is excluded from screen recordings and screenshots.

## First run

1. Level the lid to the angle you want using your phone.
2. Press `⌃⌥⇧L`, then `C` to store it.
3. Press `Esc`.

The target persists across launches and reboots.

## Configuration

Tolerance defaults to 0.5°. To tighten it:

```shell
defaults write com.nconanthiley.mbangle toleranceDegrees -float 0.3
```

## Notes

- The hotkey uses Carbon `RegisterEventHotKey`, deliberately **not** a
  `CGEventTap`. An event tap would require Accessibility access and would list
  the app in System Settings > Privacy & Security. This approach needs no
  permission and creates no such entry.
- The sensor is polled only while the readout is on screen; the app is idle
  otherwise.
- Requires a Mac with a lid angle sensor (2019 16" MacBook Pro and later).
  Reported not to work on M1/M2 machines.
- Sensor reading code derived from Sam Gold's
  [LidAngleSensor](https://github.com/samhenrigold/LidAngleSensor) (MIT).
