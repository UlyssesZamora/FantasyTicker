# FantasyTicker

A small macOS app that shows your live ESPN fantasy football matchup in a floating, draggable, always-on-top window and in the menu bar.

- Live score vs. your opponent, with projections
- League switcher for multiple leagues
- 🏈 when one of your players' teams has the ball, 🔴 when they're in the red zone
- 🛡️ when your D/ST is on the field (⚠︎ when the opponent is in the red zone)
- ⌃⌥F shows/hides the window

## Build

```sh
./build.sh
open FantasyTicker.app
```

Requires the Xcode command line tools (`swiftc`), macOS 13+.

## Setup

Open **Settings…** from the window or the menu bar and enter:

- **League IDs** — the number after `leagueId=` in your league's URL on fantasy.espn.com
- **SWID** and **espn_s2** — cookies from fantasy.espn.com (Chrome: ⌥⌘I → Application → Cookies). Needed for private leagues.

Settings are stored locally in `~/Library/Application Support/FantasyTicker/config.json`.

## Testing without an ESPN login

`FT_DEMO=1 ./FantasyTicker.app/Contents/MacOS/FantasyTicker` fills the window with fake players on real, live NFL games. Add `FT_SNAPSHOT=/tmp/shot.png` to save a picture of the window.

Uses ESPN's unofficial fantasy API and public NFL scoreboard, which may change without notice.
