# Meeting Reminders

Tiny macOS background apps that pop a playful animation across your screen a
few minutes before every calendar (e.g. Outlook) meeting, with a banner
showing the meeting title, start time and "in N min".

Two independent variants are built from the same calendar code:

| Variant | Animation | App / executable | Bundle id (prefs domain) | Logs |
|---|---|---|---|---|
| **Meeting Airplane** | cartoon plane towing a pink banner, left → right | `MeetingAirplane` | `com.user.meetingairplane` | `/tmp/meetingairplane.{out,err}.log` |
| **Meeting Cat** | walking cat with a sky-blue banner, right → left | `MeetingCat` | `com.user.meetingcat` | `/tmp/meetingcat.{out,err}.log` |

Both read from the macOS Calendar app (where your Outlook/Exchange account
already lives), so there's no API key, no OAuth, no server. Each runs as a
launchd background agent — no Dock icon, no menu bar item. Only one variant
is installed at a time; installing one replaces the other.

> Based on [meeting-airplane](https://github.com/aam11/meeting-airplane) by
> Anish Aniket Mahanta — see [Credits](#credits).

## Install

Clone the repository and install the reminder variant you want:

```bash
git clone https://github.com/chauhanunnati/meeting-reminders.git
cd meeting-reminders

./install.sh          # Meeting Airplane
./install.sh cat      # Meeting Cat
```

This compiles the chosen app, copies it to `~/Applications/`, registers and
starts its launchd agent, and removes the other variant if it is installed.
Only one reminder app runs at a time; to switch, run the install command for
the other variant. Requires macOS 11+ and Xcode Command Line Tools
(`xcode-select --install` if needed).

## First-launch permission

The first time the app reads your calendar, macOS asks for permission. Grant
it. If you miss the popup, go to **System Settings → Privacy & Security →
Calendars** and enable *MeetingAirplane* or *MeetingCat*, whichever you
installed.

## Make sure Outlook is in Calendar.app

The apps read the built-in Calendar app, not Outlook directly. If your
Outlook account isn't there yet:

- Go to **System Settings → Internet Accounts → Microsoft Exchange** (or
  Outlook), then sign in.
- Open Calendar.app once and confirm your Outlook events appear.

After that, new and updated meetings are picked up automatically.

## Preview the animation right now

You don't have to wait for a real meeting. Build and play either animation
with a dummy meeting title:

```bash
# Meeting Airplane
./build.sh airplane
build/MeetingAirplane.app/Contents/MacOS/MeetingAirplane --test

# Meeting Cat
./build.sh cat
build/MeetingCat.app/Contents/MacOS/MeetingCat --test
```

The preview plays once, then quits. To preview an already installed app, run:

```bash
~/Applications/MeetingAirplane.app/Contents/MacOS/MeetingAirplane --test
~/Applications/MeetingCat.app/Contents/MacOS/MeetingCat --test
```

Running `./build.sh` without an argument builds both apps into `build/`.

## Uninstall

```bash
./uninstall.sh          # Meeting Airplane
./uninstall.sh cat      # Meeting Cat
```

Removes the launch agent and the installed `.app`. Calendar permission is
left in place (revoke it in System Settings if you want).

## How it works

- A timer (default every 30s) asks EventKit for events in the next two hours.
- Each event starting within the lead window (default 5 min) fires the
  animation once. Dedup is keyed on `(event-id, start-time)`, so recurring
  meetings fire once per occurrence.
- The overlay is a borderless, transparent, click-through, non-activating
  panel above everything (including full-screen apps); clicks pass through.
- A manual 60Hz `Timer` slides the window across the screen and fades it out
  at the end. Meeting Cat also steps through its 24-frame walk cycle on the
  same timer.

## Configuration

Runtime settings live in `UserDefaults` under each app's bundle id. Use the
`defaults` CLI (shown for the cat; swap in `com.user.meetingairplane` for
the plane):

```bash
# Time to cross the screen in seconds (default: cat 12, airplane 6)
defaults write com.user.meetingcat slideDuration -float 15

# Fire 10 minutes early instead of 5 (default: 5)
defaults write com.user.meetingcat leadMinutes -int 10

# Poll every 60 seconds instead of 30 (default: 30)
defaults write com.user.meetingcat pollSeconds -float 60

# Fade-out length in seconds (default: 0.6)
defaults write com.user.meetingcat fadeDuration -float 1

# Tolerance band around the lead time, in seconds (default: 60). With the
# defaults a meeting fires once when it's 4–6 minutes away. Set to 0 to fire
# as soon as a meeting is within leadMinutes.
defaults write com.user.meetingcat triggerBandSeconds -float 60

# Restart the agent to pick up changes
launchctl kickstart -k "gui/$(id -u)/com.user.meetingcat"
```

Out-of-range values clamp to safe limits; missing values use defaults.
Reset with `defaults delete com.user.meetingcat` and restart the agent.

## Project structure

```
Sources/
  Shared/     calendar polling, config, app entry point (used by both apps)
  Airplane/   airplane overlay + per-app constants (Variant.swift)
  Cat/        cat overlay + per-app constants (Variant.swift)
art/
  plane.png, banner.png   airplane art (banner is recolored at runtime for the cat)
  cat/                    cat walk-cycle frames (cat_000.png … cat_023.png)
  LICENSE-art.txt         artwork credits and licenses
tools/
  extract-frames.swift    turns a green-screen video into transparent PNG frames
Info-Airplane.plist, Info-Cat.plist   app bundle metadata per variant
build.sh, install.sh, uninstall.sh    take an optional `airplane` | `cat` argument
docs/                     original meeting-airplane design notes/roadmap
```

To tweak visuals, edit `Sources/Cat/OverlayController.swift` (cat size,
banner color, text color are at the top of `makeContentView`) or
`Sources/Airplane/OverlayController.swift`, then rebuild/reinstall.

### Regenerating the cat frames

The frames in `art/cat/` are committed, so this is only needed if you want
to change them. Download the source video from
[Pixabay](https://pixabay.com/videos/cat-walk-walking-animal-pet-2d-92641/)
and save it as `art/source/cat_moving.mp4` (ignored by git), then:

```bash
swiftc -O -o /tmp/extract-frames tools/extract-frames.swift
/tmp/extract-frames art/source/cat_moving.mp4 art/cat
```

## Credits

- **Original project:** [meeting-airplane](https://github.com/aam11/meeting-airplane)
  by **Anish Aniket Mahanta**, released under the MIT License. Meeting
  Airplane in this repo is that project's app, preserved as-is; the calendar
  logic shared by both variants comes from it too. The original copyright
  notice is kept in [`LICENSE`](LICENSE).
- **Plane and banner artwork:** [@conniexu444](https://github.com/conniexu444),
  from [meeting-reminder](https://github.com/conniexu444/meeting-reminder)
  (MIT).
- **Cat animation:** frames derived from a
  [Pixabay video](https://pixabay.com/videos/cat-walk-walking-animal-pet-2d-92641/)
  under the Pixabay Content License.

Full artwork license details: [`art/LICENSE-art.txt`](art/LICENSE-art.txt).

## License

MIT — see [`LICENSE`](LICENSE).
