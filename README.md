# Lights Out

A menu-bar app that keeps your Mac **awake and unlocked** for UI-automation agents while the **screen is dark**,
so it isn't lighting up the room or spending energy on the backlight.

**[Download for Mac](https://github.com/vunguyentuan/lightsout/releases/latest/download/LightsOut.dmg)** (macOS 14+, Apple Silicon, notarized) · **[Website](https://lightsout.madebyvu.com)**

## The problem

Agents that drive the UI (computer-use agents, AppleScript/Accessibility automation, test runners) stop working once
the screen locks. The obvious fixes conflict:

- Let the display sleep to save power → macOS locks the session ("Require password after display is turned off").
- `caffeinate -d` → no lock, but the screen stays lit all night.

## How it works

| Piece | What it does |
| --- | --- |
| **Keep Mac Awake & Unlocked** | Holds `PreventUserIdleDisplaySleep` + `PreventUserIdleSystemSleep` power assertions and declares user activity every 30 s. The display never *idles* to sleep, so the screen saver and display-sleep lock never start. |
| **Lights Out** | Turns the light off *without* telling macOS the display is off: every display's gamma table is set to black and the backlight goes to 0 (DisplayServices for built-in/Apple displays, DDC/CI for external monitors). Gamma is applied after the framebuffer, so **screenshots and screen recordings still see the real desktop**. Agents keep working normally. |
| **Wake on physical input** | Real mouse, trackpad, or keyboard input brings the screen back. Input synthesized by agents doesn't: every `CGEvent.post` carries the poster's PID, and hardware events carry 0. |
| **Stay Awake with Lid Closed** | A closed MacBook lid sleeps the Mac whenever no display is on, for example when you switch the external monitor off, and no power assertion can stop that. With this on, a small root helper turns on `pmset disablesleep` while Keep Awake is on and the Mac is on AC power. It turns it back off on battery and when Lights Out quits or crashes, and never touches a `disablesleep` you set yourself. |
| **Auto Lights Out** | Goes dark after N minutes without *physical* input (default 10), replacing normal display sleep. |
| **Safety** | macOS restores gamma automatically when the app exits, even on a crash. Backlight values are restored on quit or `SIGTERM`. After a hard crash they're restored on the next launch. |

Verified on an M4 Pro MacBook Pro (clamshell) driving an LG 27UP850 over DisplayPort: while dark, gamma is 0 and DDC
brightness is 0/100, but screenshots show the same desktop as when lit. Agent mouse, scroll, and key events don't wake
it, and the session stays unlocked past the 10-minute display-sleep timer with "require password: immediately" set.

## Use

- Menu-bar icon: ☕ awake · 🌙 lights out · 💤 inactive.
- **⌃⌥⌘L** toggles Lights Out from anywhere. No permission needed.
- **Brightness** sliders in the menu set each display's backlight: built-in and Apple displays through
  DisplayServices, external monitors over DDC/CI (same requirements as below). They're disabled while dark.
- From scripts or agents:

  ```sh
  open -g lightsout://dark       # screen off, Mac keeps working
  open -g lightsout://light      # screen on
  open -g lightsout://toggle
  open -g lightsout://awake/on   # or awake/off
  open -g lightsout://brightness/50   # every display, 0-100 (ignored while dark)
  open -g lightsout://auto-brightness/on   # or auto-brightness/off
  open -g lightsout://lid-awake/on   # or lid-awake/off
  ```

### Auto brightness from an external light sensor

The Mac's own light sensor is in the lid, so it reads 0 lux in clamshell. Lights Out can follow any other sensor
instead: point it at an executable that streams one reading per line to stdout, either `<lux>` or
`<unix_epoch> <lux>` (for example, a script that reads an Android phone's sensor over adb):

```sh
defaults write com.vunguyen.LightsOut luxCommand /path/to/your-lux-command
```

**Auto Brightness** then appears under the brightness sliders and shows the current reading. Brightness follows a
log curve of lux, averaged over a few seconds, and changes only in steps of 3% or more, so it doesn't flicker. Turning
it on keeps each display at its current level, and from then on brightness follows changes in the light. Moving a
slider teaches it your preferred level for that display. It pauses while the screen is dark, and holds the last
level if the sensor stops reporting. The command is restarted if it exits.

### Optional permissions

- **Allow in the Background** (System Settings → General → Login Items & Extensions): needed once for
  *Stay Awake with Lid Closed*. Its helper runs as root because `pmset disablesleep` is a system setting. It accepts
  requests only from Lights Out signed by the same developer, can change nothing but that one setting, and exits
  when Lights Out isn't using it. While it's holding the setting, Sleep in the Apple menu does nothing.

- **Accessibility** (menu → *Allow Keyboard Detection…*): lets a physical key press wake the screen. Without it only
  the mouse/trackpad wakes it, though the hotkey always works. Also required by *Simulate Activity*.
- **Simulate Activity (Managed Macs)**: if an MDM profile forces a screen saver/lock based on the HID idle timer,
  this posts a zero-distance mouse move after 50 s of no input. It never fires while a mouse button is held.

## Build

Requires Xcode 15+ (Swift 5.10+), macOS 14+.

```
make run       # build → build/LightsOut.app, then launch
make install   # copy to /Applications and launch (Launch at Login works best from there)
make test      # unit tests
make release   # Developer ID sign + notarize → build/LightsOut.dmg, appcast, Homebrew cask (needs your own certificate and `npm i -g create-dmg`)
make publish   # GitHub release + deploy the site and Sparkle appcast (notes from release-notes/<version>.md)
```

Development builds are signed with your Apple Development certificate when you have one, so the Accessibility grant
survives rebuilds (override with `DEV_SIGN_IDENTITY=...`). Updates are delivered with Sparkle from
`lightsout.madebyvu.com/appcast.xml`. The site in `site/` is deployed with Cloudflare Workers static assets.

## Limitations

- **The session is unlocked while dark.** Anyone at the keyboard can use it. Use this where that's acceptable.
- **Lid closed on battery:** *Stay Awake with Lid Closed* only works on AC power. On battery, a closed lid still
  sleeps the Mac, so it can't overheat in a bag.
- External-monitor backlight control needs DDC/CI (Apple Silicon only, and the monitor's DDC/CI setting enabled).
  Without it, the pixels are still black, but an LCD backlight stays on.
- A manual lock (⌃⌘Q, Lock Screen) still locks. Lights Out only prevents *idle* locking.
