# CasinoComputerCraft — Project Context

## Overview
A full casino system for ComputerCraft (Minecraft mod). Players use pocket PCs to log in, manage chips, and play games. A central DB server handles accounts. Games sync chips with the DB on exit.

**Repo:** https://github.com/Sinsan02/CasinoComputerCraft  
**Install:** `wget https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/install.lua`

---

## File Structure

```
install.lua              Root installer — menu 1-6, downloads everything
casino/
  db.lua                 Rednet DB server (protocol "casino")
  client.lua             Pocket PC app — login, chip balance, launch games
  admin.lua              Cashier terminal — add/set chips for users
  install.lua            Old sub-installer (kept but superseded by root install.lua)
poker/
  cards.lua              Deck/card utilities
  eval.lua               Hand evaluator (5-card best hand)
  dealer.lua             Poker table PC — manages game, monitor display
  player.lua             Poker pocket PC — connects to dealer, casino session aware
roulette/
  table.lua              Roulette table PC — 4x6 monitor array, full animated wheel
  player.lua             Roulette pocket PC — betting UI, casino session aware
```

---

## Architecture

### Casino Session File
Before launching a game, `casino/client.lua` writes `/casino_session`:
```lua
{username="...", password="...", chips=N, is_admin=false}
```
The game (poker/player.lua or roulette/player.lua) reads and deletes this file on startup. If absent, falls back to manual prompts.

### Casino DB (`casino/db.lua`)
- Protocol: `"casino"`
- Stores users at `/casino_data/users/<username>`
- First registered user automatically becomes admin (`is_admin=true`)
- Password stored as djb2 hash
- Request types:
  - `register` — {username, password}
  - `login` — {username, password} → {ok, chips, is_admin}
  - `get_balance` — {username} → {ok, chips}
  - `add_chips` — {admin, pass, target, amount}
  - `set_chips` — {admin, pass, target, amount}
  - `update_chips` — {username, delta} — used by games (delta can be negative)
  - `list_users` — {admin, pass} → {ok, users=[{username,chips,is_admin}]}

### Casino Client (`casino/client.lua`)
- Session stored as: `{username, password, chips, is_admin}`
- Screens: login/register → main (balance + game buttons) → game launch
- Admin users see yellow ADMIN PANEL button embedded in main screen
- Admin panel: list users, add chips, set chips (click-to-pick user list)
- `refreshBalance()` called after returning from any game

### Poker (`poker/dealer.lua` + `poker/player.lua`)
- Protocol: `"poker"`
- `player.lua` reads casino session → uses username, fetches live balance
- On Q (quit): sends `update_chips` delta to casino DB
- Dealer shows English labels (translated from Norwegian)

### Roulette (`roulette/table.lua` + `roulette/player.lua`)
- Protocols: table uses `"roulette"` + `"casino"`
- Table requires 4x6 monitor array + wireless modem + casino_db running
- `mon.setTextScale(0.5)`, `MW, MH = mon.getSize()`
- After each round: sends `update_chips` delta for every player with bets
- Player reads `/casino_session` — errors if not present (must launch via casino_app)

---

## UI Conventions
- **All menus use mouse_click buttons** — never number-key menus
- Button system in client.lua: `addBtn(id,y,text,bg,fg)`, `rawAddBtn(id,x,y,w,text,bg,fg)`, `drawBtns()`, `clickBtn(mx,my)`
- Monitor helpers in roulette/table.lua: `mset`, `mfill`, `mwrite`, `mwriteC`
- All text is in **English** (translated from Norwegian)

---

## Roulette Table Detail

### WHEEL array (37 positions, real roulette order)
```lua
{0,32,15,19,4,21,2,25,17,34,6,27,13,36,11,30,8,23,10,5,24,16,33,1,20,14,31,9,22,18,29,7,28,12,35,3,26}
```

### Phases
`waiting` → `betting` (25s timer) → `spinning` (animation) → `result` (7s) → `waiting`  
Monitor touch or ENTER advances from waiting/result.

### Animation
`buildAnim(result)` pre-computes a frame array with speed profile:
- 18 frames at speed 5, 18 at 4, 14 at 3, 14 at 2, 12 at 1, then extra steps to land exactly on result
- `ANIM_DELAYS`: frames 1-18=0.04s, 19-36=0.07s, 37-50=0.12s, 51-64=0.20s, 65+=0.30s

### Bet types & payouts
| type | payout |
|------|--------|
| number (0-36) | 35:1 |
| red/black/even/odd/low/high | 1:1 |
| dozen1/2/3 | 2:1 |
| col1/col2/col3 | 2:1 |

### Chip sizes (player.lua)
1, 5, 10, 25, 50, 100, 500

---

## Known Issues / Fixed Bugs
- `colors.teal` does not exist in CC → replaced with `colors.cyan` everywhere
- `colors.orange` may not resolve on all CC versions → replaced with `colors.yellow` in column bet cells
- `mfill`/`mset` nil color guard added: `bg or colors.black`, `fg or colors.white`
- Raise input in poker used `read()` which prefixed 'r' key → fixed with char events
- Turn buttons derived from `currentPlayer` in state message to avoid stale state
- Player leaving mid-game now advances betting turn if it was their turn

---

## ComputerCraft Color Reference
Valid `colors.*` constants (all are powers of 2):
`white(1) orange(2) magenta(4) lightBlue(8) yellow(16) lime(32) pink(64) gray(128) lightGray(256) cyan(512) purple(1024) blue(2048) brown(4096) green(8192) red(16384) black(32768)`  
No `teal`, no `darkBlue`, no `darkGreen` etc.

---

## Economy
- 1 chip = 1 kr
- Players buy chips at cashier (admin terminal or admin in client app)
- Chips persist in casino DB across sessions and games
- Games never give chips from thin air — always delta from what player started with
