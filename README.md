# FantasyTicker 🏈

Vibe coded app to show my fantasy football matchups because I'm too lazy to look at my phone or open the website while I'm doing other stuff.

It's a little window that floats in the corner of your Mac and tells you:

- the score of your matchup (and whether you should be nervous)
- 🏈 when one of your guys' teams has the ball
- 🔴 when one of your guys is in the red zone (lock in)
- 🛡️ when your defense is on the field
- what your opponent's players are up to, so you can root against them

Drag it anywhere, switch between leagues, or hide it with ⌃⌥F when your boss walks by.

## Setup

```sh
./build.sh
open FantasyTicker.app
```

Then open **Settings…** and paste in:

- **League IDs**: the number after `leagueId=` in your league's URL on fantasy.espn.com
- **SWID** and **espn_s2**: cookies from fantasy.espn.com (Chrome: ⌥⌘I → Application → Cookies). You need these for private leagues.

Your cookies stay on your Mac. Uses ESPN's unofficial API, so if it breaks one Sunday, that's why.
