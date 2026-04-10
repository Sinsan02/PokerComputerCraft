# CasinoComputerCraft

A Casino + Texas Hold'em Poker system for [CC:Tweaked](https://tweaked.cc/) (ComputerCraft) in Minecraft.  
Supports multiple players over wireless rednet, a central database server for chip balances, and a 4×4 monitor display for the dealer table.

---

## System Overview

```
┌─────────────┐      wireless rednet      ┌──────────────┐
│  DB Server  │◄────────────────────────►│ Casino Client│  (player pocket PC)
│ (casino_db) │                           └──────────────┘
└─────────────┘
       ▲
       │ wireless rednet
       ▼
┌─────────────┐      wireless rednet      ┌──────────────┐
│   Dealer    │◄────────────────────────►│    Player    │  (up to 5 pocket PCs)
│  (dealer)   │                           └──────────────┘
└─────────────┘
       │
  4×4 monitor
```

| Computer | Program | Role |
|---|---|---|
| Any CC computer | `casino_db` | Database server — stores chip balances |
| Any CC computer | `casino_admin` | Admin cashier — add/set chips, list users |
| Pocket PC / player computer | `casino_app` | Casino client — register, login, launch games |
| CC computer + 4×4 monitor | `dealer` | Poker dealer table — runs the game, shows monitor |
| Pocket PC | `player` | Poker player — cards, betting, hand display |

---

## Requirements

- **CC:Tweaked** mod installed
- **Wireless modem** on every computer
- **4×4 Advanced Monitor** adjacent to the dealer computer
- Internet access (for initial `wget` download)

---

## Installation

### Option A — Casino installer (installs everything)

On any CC computer with internet access:

```
wget https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/casino/install.lua install
install
```

Choose what to install (1–5). Option **5 = All** downloads all components.

| Choice | Installs | Shortcut created |
|---|---|---|
| 1 | Casino client | `casino_app` |
| 2 | Admin terminal | `casino_admin` |
| 3 | Database server | `casino_db` |
| 4 | Poker (dealer + player) | `dealer`, `player` |
| 5 | Everything above | all shortcuts |

### Option B — Poker only

```
wget https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/poker/install.lua install
install
```

Creates shortcuts `dealer` and `player`.

---

## Setup & Start Order

1. **DB Server** — start first on a dedicated computer:
   ```
   casino_db
   ```
   The first user to register automatically becomes admin.

2. **Dealer table** — on the computer with the 4×4 monitor attached:
   ```
   dealer
   ```
   Press **Enter** to start a round once ≥ 2 players have joined.

3. **Players** — each on their own pocket PC:
   ```
   player
   ```
   If started via `casino_app` after login, chips are synced automatically from/to the DB.

4. **Admin** (optional) — to manage balances:
   ```
   casino_admin
   ```

---

## Poker — How to Play

Players connect automatically when running `player`. The dealer sees them appear on the monitor and on the terminal.

### Dealer controls
| Key | Action |
|---|---|
| Enter | Start game / Start new round |

### Player controls
| Key | Action |
|---|---|
| C | Check (if no bet) / Call |
| R | Raise (prompts for amount) |
| F | Fold |
| A | All-in |
| Q | Quit (chips synced to DB) |

Chips are saved to the casino DB automatically after every round and on quit.

---

## Monitor Display (dealer)

The 4×4 monitor at `setTextScale(0.75)` shows:
- **Header** — game title + current phase / whose turn it is
- **5 player seats** in a half-circle (top row + sides, no bottom)
  - Each seat: name, mini cards (hidden when folded), balance, chip visualization, bet, status
  - Active player highlighted in cyan, winner in yellow
- **Community cards** (5 cards, 5×9 each) centered on the table
- **Pot** — bold black banner with amount, chip row centered below

---

## File Structure

```
casino/
  db.lua        — Database server (chip storage, user accounts)
  client.lua    — Casino client app (login, register, launch games)
  admin.lua     — Admin cashier terminal
  install.lua   — Casino installer

poker/
  dealer.lua    — Dealer logic + monitor UI
  player.lua    — Player client
  cards.lua     — Deck, suits, card helpers
  eval.lua      — Hand evaluator (Texas Hold'em)
  install.lua   — Poker installer
```

---

## Notes

- A player without a casino account can still join poker manually with a local balance (not saved to DB).
- The DB uses a simple djb2 hash for passwords — suitable for a Minecraft private server, not production use.
- Maximum 5 players per poker table.
- Minimum 2 players to start a round.
