-- dealer.lua
-- Texas Hold'em Dealer with betting
-- Dealer presses ENTER to start a round and to start a new round after showdown
-- Everything else (flop/turn/river/showdown) happens automatically when all players have acted

local dir   = fs.getDir(shell.getRunningProgram())
local cards = dofile(fs.combine(dir, "cards.lua"))
local eval  = dofile(fs.combine(dir, "eval.lua"))

local PROTOCOL   = "txpoker"
local MIN_PLAYERS = 2
local MAX_PLAYERS = 5
local MIN_RAISE   = 10

-- =====================================================
-- PERIPHERALS
-- =====================================================
local mon = peripheral.find("monitor")
if not mon then
    print("ERROR: No monitor found!"); return
end
mon.setTextScale(0.75)

local modemName
for _, name in ipairs(peripheral.getNames()) do
    local t = peripheral.getType(name)
    if t == "modem" then
        local p = peripheral.wrap(name)
        if p.isWireless and p.isWireless() then modemName = name; break end
    end
end
if not modemName then print("ERROR: No wireless modem found!"); return end
rednet.open(modemName)

-- =====================================================
-- GAME STATE
-- =====================================================
local game = {
    phase       = "lobby",
    deck        = {},
    community   = {},
    players     = {},
    -- Player fields: {id, name, hand, balance, roundBet, totalBet, folded, allIn, acted}
    pot         = 0,
    currentBet  = 0,
    actionIdx   = 1,   -- index in game.players for whose turn it is
    betting     = false,
    winner      = nil,
    winHand     = nil,
    results     = {},
}

-- =====================================================
-- NETWORK
-- =====================================================
local function sendTo(id, msg)
    rednet.send(id, textutils.serialize(msg), PROTOCOL)
end

local function broadcast(msg)
    rednet.broadcast(textutils.serialize(msg), PROTOCOL)
end

local function playerDataList()
    local list = {}
    for _, p in ipairs(game.players) do
        list[#list + 1] = {
            name     = p.name,
            balance  = p.balance,
            roundBet = p.roundBet,
            folded   = p.folded,
            allIn    = p.allIn,
        }
    end
    return list
end

local function currentPlayerName()
    if game.betting and game.players[game.actionIdx] then
        return game.players[game.actionIdx].name
    end
    return nil
end

local function broadcastState()
    broadcast({
        type          = "state",
        phase         = game.phase,
        community     = game.community,
        pot           = game.pot,
        currentBet    = game.currentBet,
        currentPlayer = currentPlayerName(),
        playerData    = playerDataList(),
        betting       = game.betting,
    })
end

-- =====================================================
-- =====================================================
-- MONITOR DRAWING
-- =====================================================
local function mfill(x1, y1, x2, y2, char, bg)
    mon.setBackgroundColor(bg or colors.green)
    local row = string.rep(char or " ", x2 - x1 + 1)
    for y = y1, y2 do mon.setCursorPos(x1, y); mon.write(row) end
end

-- Chip visualization
local CHIP_DENOM = {
    {val=1000, clr=colors.red},
    {val=500,  clr=colors.purple},
    {val=100,  clr=colors.blue},
    {val=25,   clr=colors.lime},
    {val=5,    clr=colors.gray},
}

local function getChipList(amount)
    local result = {}
    local rem = math.max(0, amount)
    for _, d in ipairs(CHIP_DENOM) do
        local cnt = math.min(math.floor(rem / d.val), 6)
        for _ = 1, cnt do result[#result+1] = d.clr end
        rem = rem % d.val
        if #result >= 18 then break end
    end
    if #result == 0 and amount > 0 then result[1] = colors.gray end
    return result
end

local function drawChipRow(x, y, amount, maxW, bg)
    bg   = bg   or colors.green
    maxW = maxW or 10
    local chips = getChipList(amount)
    local count = math.min(#chips, maxW)
    mon.setCursorPos(x, y)
    for i = 1, count do
        mon.setBackgroundColor(chips[i])
        mon.write(" ")
    end
    if count < maxW then
        mon.setBackgroundColor(bg)
        mon.write(string.rep(" ", maxW - count))
    end
    mon.setBackgroundColor(bg)
    return count
end

-- Community card (5w x 9h)
local function drawMonCard(mx, my, card)
    if not card then
        mon.setBackgroundColor(colors.green)
        mon.setTextColor(colors.lime)
        local empty = {"+---+","|   |","|   |","| ? |","|   |","| ? |","|   |","|   |","+---+"}
        for dy, row in ipairs(empty) do
            mon.setCursorPos(mx, my + dy - 1); mon.write(row)
        end
        return
    end
    local sClr = cards.CLR[card.suit]
    local vL = string.format("%-3s", card.value):sub(1, 3)
    local vR = string.format("%3s",  card.value):sub(-3)
    mon.setBackgroundColor(colors.white)
    mon.setTextColor(colors.black)
    mon.setCursorPos(mx,     my    );  mon.write("+---+")
    mon.setCursorPos(mx,     my + 1);  mon.write("|   |")
    mon.setCursorPos(mx + 1, my + 1);  mon.setTextColor(sClr); mon.write(vL)
    mon.setCursorPos(mx,     my + 2);  mon.setTextColor(colors.black); mon.write("|   |")
    mon.setCursorPos(mx,     my + 3);  mon.write("|   |")
    mon.setCursorPos(mx + 2, my + 3);  mon.setTextColor(sClr); mon.write(cards.SYM[card.suit])
    mon.setCursorPos(mx,     my + 4);  mon.setTextColor(colors.black); mon.write("|   |")
    mon.setCursorPos(mx,     my + 5);  mon.write("|   |")
    mon.setCursorPos(mx,     my + 6);  mon.write("|   |")
    mon.setCursorPos(mx + 1, my + 6);  mon.setTextColor(sClr); mon.write(vR)
    mon.setCursorPos(mx,     my + 7);  mon.setTextColor(colors.black); mon.write("|   |")
    mon.setCursorPos(mx,     my + 8);  mon.write("+---+")
end

-- Mini card (3w x 1h); bg = surrounding background color
local function drawMiniCard(mx, my, card, faceDown, bg)
    bg = bg or colors.green
    mon.setCursorPos(mx, my)
    if faceDown or not card then
        mon.setBackgroundColor(colors.blue)
        mon.setTextColor(colors.lightBlue)
        mon.write("???")
    else
        mon.setBackgroundColor(colors.white)
        mon.setTextColor(cards.CLR[card.suit])
        mon.write(string.format("%-3s", card.value .. cards.SYM[card.suit]):sub(1, 3))
    end
    mon.setBackgroundColor(bg)
end

-- Player slot (slotW x 4 rows):
--   Row 0: idx + name + [F/A] tag
--   Row 1: mini-cards + balance
--   Row 2: chip row + bet amount
--   Row 3: YOUR TURN / WINNER / hand name / folded
local function drawPlayerSlot(x, y, player, idx, slotW)
    local isCurrent = game.betting and game.players[game.actionIdx] == player
    local isWinner  = game.winner and (
        game.winner == player.name or
        game.winner:find(player.name, 1, true) ~= nil
    )

    -- Lime background: bright on green table, good contrast
    local slotBg = isCurrent and colors.cyan or colors.lime
    mon.setBackgroundColor(slotBg)
    for dy = 0, 3 do
        mon.setCursorPos(x, y + dy)
        mon.write(string.rep(" ", slotW))
    end

    -- Row 0: idx + name + tag
    local tag = player.folded and "[F]" or (player.allIn and "[A]" or "")
    local nameMax = slotW - #tag - 3
    local nameStr = string.format("%-" .. slotW .. "s",
        idx .. ". " .. player.name:sub(1, nameMax) .. tag):sub(1, slotW)
    local nameClr = colors.black
    if isWinner        then nameClr = colors.yellow
    elseif isCurrent   then nameClr = colors.black
    elseif player.folded then nameClr = colors.gray
    end
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(slotBg)
    mon.setTextColor(nameClr)
    mon.write(nameStr)

    -- Row 1: mini-cards + balance
    if player.folded then
        -- Hide cards when folded
        mon.setBackgroundColor(slotBg)
        mon.setCursorPos(x, y+1)
        mon.setTextColor(colors.gray)
        mon.write(string.format("%-" .. slotW .. "s", "[folded]"):sub(1, slotW))
    else
        local showFace = (game.phase == "showdown")
        drawMiniCard(x,   y+1, player.hand and player.hand[1], not showFace, slotBg)
        mon.setBackgroundColor(slotBg); mon.setCursorPos(x+3, y+1); mon.write(" ")
        drawMiniCard(x+4, y+1, player.hand and player.hand[2], not showFace, slotBg)
    end
    mon.setBackgroundColor(slotBg)
    mon.setTextColor(colors.black)
    mon.setCursorPos(x+8, y+1)
    mon.write(string.format("$%d", player.balance):sub(1, slotW - 8))

    -- Row 2: chip row + bet amount
    drawChipRow(x, y+2, player.roundBet, 6, slotBg)
    mon.setBackgroundColor(slotBg)
    mon.setTextColor(colors.black)
    mon.setCursorPos(x+7, y+2)
    mon.write(string.format("$%d", player.roundBet):sub(1, slotW - 7))

    -- Row 3: action / status
    mon.setCursorPos(x, y+3)
    if isCurrent then
        mon.setBackgroundColor(colors.cyan)
        mon.setTextColor(colors.black)
        mon.write(string.format("%-" .. slotW .. "s", ">> YOUR TURN"):sub(1, slotW))
    elseif isWinner then
        mon.setBackgroundColor(colors.yellow)
        mon.setTextColor(colors.black)
        mon.write(string.format("%-" .. slotW .. "s", "** WINNER! **"):sub(1, slotW))
    elseif game.phase == "showdown" and not player.folded then
        mon.setBackgroundColor(colors.lime)
        mon.setTextColor(colors.black)
        local handName = ""
        for _, r in ipairs(game.results) do
            if r.name == player.name then handName = r.handName; break end
        end
        mon.write(handName:sub(1, slotW))
    else
        mon.setBackgroundColor(slotBg)
        mon.setTextColor(colors.gray)
        local status = player.folded and "--- folded ---" or ""
        mon.write(string.format("%-" .. slotW .. "s", status):sub(1, slotW))
    end
    mon.setBackgroundColor(colors.green)
end

local function drawEmptySlot(x, y, idx, slotW)
    -- Green background (matches table)
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.lime)
    for dy = 0, 3 do
        mon.setCursorPos(x, y + dy)
        mon.write(string.rep(" ", slotW))
    end
    mon.setCursorPos(x, y)
    mon.write((idx .. ". [ empty ]"):sub(1, slotW))
end

local function drawTable()
    local W, H = mon.getSize()
    mfill(1, 1, W, H, " ", colors.green)

    -- slotW: divide into ~4 columns, clamped 10-18
    local SLOT_H = 4
    local slotW  = math.max(10, math.min(18, math.floor((W - 4) / 4)))

    -- Community cards: 5 x (5w+1spacing) = 29 wide, 9 tall
    local cardH   = 9
    local totalCW = 29
    local cardX   = math.max(slotW + 2, math.floor((W - totalCW) / 2) + 1)
    local cardY   = math.max(SLOT_H + 4, math.floor((H - cardH) / 2))

    -- Seat X anchors
    local leftX   = 1
    local rightX  = W - slotW
    local centerX = math.floor(W / 2) - math.floor(slotW / 2)
    local hasCenter = (centerX > leftX + slotW + 1) and
                      (centerX + slotW - 1 < rightX - 1)

    -- Half-circle: top 3 + mid 2 flanking cards, no bottom row
    --   2 (top-left)   3 (top-center*)   4 (top-right)
    --   1 (mid-left)   [community cards] 5 (mid-right)
    local topY = 3
    local midY = cardY
    local seats
    if hasCenter then
        seats = {
            {leftX,   midY},
            {leftX,   topY},
            {centerX, topY},
            {rightX,  topY},
            {rightX,  midY},
        }
    else
        local row2Y = topY + SLOT_H + 1
        seats = {
            {leftX,  midY},
            {leftX,  topY},
            {rightX, topY},
            {rightX, row2Y},
            {leftX,  row2Y},
        }
    end

    for i = 1, 5 do
        local sx, sy = seats[i][1], seats[i][2]
        if game.players[i] then
            drawPlayerSlot(sx, sy, game.players[i], i, slotW)
        else
            drawEmptySlot(sx, sy, i, slotW)
        end
    end

    -- Header row 1 (drawn after seats so title stays visible)
    local title = "=== TEXAS HOLD'EM ==="
    mon.setCursorPos(math.floor((W - #title) / 2) + 1, 1)
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.yellow)
    mon.write(title)

    -- Phase / turn row 2
    local phaseNames = {
        lobby="LOBBY", deal="CARDS DEALT",
        flop="FLOP", turn="TURN", river="RIVER", showdown="SHOWDOWN"
    }
    local phStr = "[ " .. (phaseNames[game.phase] or game.phase:upper()) .. " ]"
    if game.betting then
        phStr = phStr .. " " .. (currentPlayerName() or "")
    end
    mon.setCursorPos(math.floor((W - #phStr) / 2) + 1, 2)
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.white)
    mon.write(phStr)

    -- Community cards
    for i = 1, 5 do
        drawMonCard(cardX + (i-1)*6, cardY, game.community[i])
    end

    -- Pot: banner text first, then chip row centered below
    local potTxtRow = cardY + cardH + 1
    local potStr = "  POT: $" .. game.pot .. "  "
    mon.setCursorPos(math.floor((W - #potStr) / 2) + 1, potTxtRow)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.yellow)
    mon.write(potStr)
    mon.setBackgroundColor(colors.green)
    if game.currentBet > 0 then
        local betStr = "  Bet: $" .. game.currentBet .. "  "
        mon.setCursorPos(math.floor((W - #betStr) / 2) + 1, potTxtRow + 1)
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.white)
        mon.write(betStr)
        mon.setBackgroundColor(colors.green)
    end
    -- Chip row centered below pot text
    local chipRow = potTxtRow + 2
    if chipRow <= H - 1 then
        local potChips = getChipList(game.pot)
        local chipW = math.min(#potChips, math.min(24, W - 4))
        if chipW > 0 then
            drawChipRow(math.floor((W - chipW) / 2) + 1, chipRow, game.pot, chipW)
        end
    end

    -- Winner banner (last row)
    if game.winner then
        local wStr = " WINNER: " .. game.winner .. " - " .. (game.winHand or "") .. " "
        if #wStr > W then wStr = wStr:sub(1, W) end
        mon.setCursorPos(math.floor((W - #wStr) / 2) + 1, H)
        mon.setBackgroundColor(colors.yellow)
        mon.setTextColor(colors.black)
        mon.write(wStr)
        mon.setBackgroundColor(colors.green)
    end

    -- Dealer ID (bottom-right)
    local idStr = "ID:" .. os.getComputerID()
    mon.setCursorPos(W - #idStr, H)
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.gray)
    mon.write(idStr)
end

-- TERMINAL
-- =====================================================
local function drawTerminal()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("=== POKER DEALER ===")
    term.setTextColor(colors.white)
    print("Phase: " .. game.phase:upper() .. "  |  ID: " .. os.getComputerID())
    print(string.rep("-", 40))
    print(string.format("%-14s %-7s %-7s %s", "Name", "Balance", "Bet", "Status"))
    print(string.rep("-", 40))
    for i, p in ipairs(game.players) do
        local status = ""
        if p.folded  then status = "FOLD"
        elseif p.allIn then status = "ALL-IN"
        elseif game.betting and i == game.actionIdx then status = "<-- TURN"
        end
        term.setTextColor(game.betting and i == game.actionIdx and colors.cyan or colors.lightGray)
        print(string.format("%-14s $%-6d $%-6d %s", p.name, p.balance, p.roundBet, status))
    end
    term.setTextColor(colors.white)
    print(string.rep("-", 40))
    print("Pot: $" .. game.pot .. "  |  Bet: $" .. game.currentBet)
    print(string.rep("-", 40))

    if game.phase == "lobby" then
        if #game.players < MIN_PLAYERS then
            term.setTextColor(colors.red)
            print("Waiting for at least " .. MIN_PLAYERS .. " players (" .. #game.players .. " now)")
        else
            term.setTextColor(colors.green)
            print("[ENTER] Start game (" .. #game.players .. " players)")
        end
    elseif game.betting then
        term.setTextColor(colors.cyan)
        print("Waiting for: " .. (currentPlayerName() or "?"))
    elseif game.phase == "showdown" then
        term.setTextColor(colors.yellow)
        if game.winner then print("WINNER: " .. game.winner) end
        term.setTextColor(colors.green)
        print("[ENTER] New round")
    end
end

-- =====================================================
-- BETTING LOGIC
-- =====================================================
local function countActive()
    local n, last = 0, nil
    for _, p in ipairs(game.players) do
        if not p.folded then n = n + 1; last = p end
    end
    return n, last
end

local function isBettingDone()
    for _, p in ipairs(game.players) do
        if not p.folded and not p.allIn then
            if not p.acted then return false end
            if p.roundBet ~= game.currentBet then return false end
        end
    end
    return true
end

local function nextActionIdx()
    local start = game.actionIdx
    for _ = 1, #game.players do
        game.actionIdx = game.actionIdx % #game.players + 1
        local p = game.players[game.actionIdx]
        if not p.folded and not p.allIn then return true end
        if game.actionIdx == start then break end
    end
    return false
end

local function notifyTurn()
    if not game.betting then return end
    local p = game.players[game.actionIdx]
    if not p then return end
    local canCheck  = (p.roundBet >= game.currentBet)
    local callAmt   = math.max(0, game.currentBet - p.roundBet)
    sendTo(p.id, {
        type       = "your_turn",
        canCheck   = canCheck,
        callAmount = callAmt,
        currentBet = game.currentBet,
        roundBet   = p.roundBet,
        balance    = p.balance,
        pot        = game.pot,
        minRaise   = MIN_RAISE,
    })
end

-- =====================================================
-- FASE-FUNKSJONER
-- =====================================================
local function startBettingRound()
    game.betting    = true
    game.currentBet = 0
    game.actionIdx  = 1
    for _, p in ipairs(game.players) do
        if not p.folded then
            p.roundBet = 0
            p.acted    = false
        end
    end
    -- Find first non-folded player
    while game.players[game.actionIdx] and game.players[game.actionIdx].folded do
        game.actionIdx = game.actionIdx + 1
        if game.actionIdx > #game.players then game.actionIdx = 1; break end
    end
    notifyTurn()
    broadcastState()
end

local function doShowdown()
    game.phase   = "showdown"
    game.betting = false
    game.results = {}

    local bestR, bestT = 0, {}
    local winners = {}

    for _, p in ipairs(game.players) do
        if not p.folded then
            local all = {}
            for _, c in ipairs(p.hand)         do all[#all+1] = c end
            for _, c in ipairs(game.community) do all[#all+1] = c end
            local r, t, name = eval.best(all)
            game.results[#game.results+1] = {name=p.name, hand=p.hand, handName=name, rank=r, ties=t}
            local cmp = eval.compare(r, t, bestR, bestT)
            if cmp > 0 then bestR, bestT = r, t; winners = {p} end
            if cmp == 0 and #winners > 0 then winners[#winners+1] = p end
        end
    end

    -- Distribute pot
    local share = math.floor(game.pot / math.max(1, #winners))
    local winNames = {}
    for _, w in ipairs(winners) do
        w.balance = w.balance + share
        winNames[#winNames+1] = w.name
    end

    game.winner  = table.concat(winNames, " & ") .. (#winners > 1 and " (Split)" or "")
    game.winHand = game.results[1] and game.results[1].handName or ""
    for _, r in ipairs(game.results) do
        for _, w in ipairs(winners) do
            if r.name == w.name then game.winHand = r.handName; break end
        end
    end

    broadcast({
        type       = "showdown",
        community  = game.community,
        results    = game.results,
        winners    = winNames,
        winHand    = game.winHand,
        playerData = playerDataList(),
        pot        = game.pot,
    })
end

local function autoWin(winner)
    winner.balance = winner.balance + game.pot
    game.winner    = winner.name
    game.winHand   = "All others folded"
    game.betting   = false
    game.phase     = "showdown"
    game.results   = {}
    broadcast({
        type       = "showdown",
        community  = game.community,
        results    = {},
        winners    = {winner.name},
        winHand    = "All others folded",
        playerData = playerDataList(),
        pot        = game.pot,
    })
end

local function checkAutoAdvance()
    -- Check if only one player remains
    local n, last = countActive()
    if n == 1 then autoWin(last); return end
    -- Check if betting round is done
    if not isBettingDone() then return end
    game.betting = false
    if     game.phase == "deal"  then
        -- Show flop
        cards.deal(game.deck)  -- burn
        for _ = 1,3 do game.community[#game.community+1] = cards.deal(game.deck) end
        game.phase = "flop"
        broadcastState()
        startBettingRound()
    elseif game.phase == "flop"  then
        cards.deal(game.deck)
        game.community[#game.community+1] = cards.deal(game.deck)
        game.phase = "turn"
        broadcastState()
        startBettingRound()
    elseif game.phase == "turn"  then
        cards.deal(game.deck)
        game.community[#game.community+1] = cards.deal(game.deck)
        game.phase = "river"
        broadcastState()
        startBettingRound()
    elseif game.phase == "river" then
        doShowdown()
    end
end

-- =====================================================
-- HANDLE BETTING ACTION FROM PLAYER
-- =====================================================
local function handleAction(senderID, msg)
    if not game.betting then return end
    local p = game.players[game.actionIdx]
    if not p or p.id ~= senderID then return end  -- not their turn

    local action = msg.action

    if action == "fold" then
        p.folded = true
        p.acted  = true

    elseif action == "check" then
        if p.roundBet < game.currentBet then return end  -- invalid
        p.acted = true

    elseif action == "call" then
        local amount = math.min(game.currentBet - p.roundBet, p.balance)
        p.balance  = p.balance  - amount
        p.roundBet = p.roundBet + amount
        p.totalBet = p.totalBet + amount
        game.pot   = game.pot   + amount
        p.acted    = true
        if p.balance == 0 then p.allIn = true end

    elseif action == "raise" then
        local raiseBy = math.max(tonumber(msg.amount) or MIN_RAISE, MIN_RAISE)
        local callAmt = math.max(0, game.currentBet - p.roundBet)
        local total   = math.min(callAmt + raiseBy, p.balance)
        p.balance  = p.balance  - total
        p.roundBet = p.roundBet + total
        p.totalBet = p.totalBet + total
        game.pot   = game.pot   + total
        game.currentBet = p.roundBet
        if p.balance == 0 then p.allIn = true end
        -- Reset others' acted flag
        for i2, p2 in ipairs(game.players) do
            if p2 ~= p and not p2.folded and not p2.allIn then
                p2.acted = false
            end
        end
        p.acted = true

    elseif action == "allin" then
        local amount = p.balance
        p.roundBet = p.roundBet + amount
        p.totalBet = p.totalBet + amount
        game.pot   = game.pot   + amount
        p.balance  = 0
        p.allIn    = true
        if p.roundBet > game.currentBet then
            game.currentBet = p.roundBet
            for _, p2 in ipairs(game.players) do
                if p2 ~= p and not p2.folded and not p2.allIn then
                    p2.acted = false
                end
            end
        end
        p.acted = true
    end

    -- Next player or end round
    if not isBettingDone() then
        nextActionIdx()
        notifyTurn()
    end
    broadcastState()
    checkAutoAdvance()
end

-- =====================================================
-- START GAME AND RESET
-- =====================================================
local function startGame()
    game.deck      = cards.newDeck()
    cards.shuffle(game.deck)
    game.community = {}
    game.winner    = nil
    game.winHand   = nil
    game.results   = {}
    game.pot       = 0
    game.currentBet = 0
    game.phase     = "deal"

    for _, p in ipairs(game.players) do
        p.hand     = {cards.deal(game.deck), cards.deal(game.deck)}
        p.roundBet = 0
        p.totalBet = 0
        p.folded   = false
        p.allIn    = false
        p.acted    = false
        sendTo(p.id, {type="hand", cards=p.hand, playerName=p.name, phase="deal"})
    end

    startBettingRound()
end

local function resetLobby()
    game.phase      = "lobby"
    game.community  = {}
    game.winner     = nil
    game.winHand    = nil
    game.results    = {}
    game.pot        = 0
    game.currentBet = 0
    game.betting    = false
    for _, p in ipairs(game.players) do
        p.hand     = {}
        p.roundBet = 0
        p.totalBet = 0
        p.folded   = false
        p.allIn    = false
        p.acted    = false
    end
    broadcast({type="lobby", playerData=playerDataList()})
end

-- =====================================================
-- HANDLE PLAYER MESSAGES
-- =====================================================
local function handlePlayerMsg(senderID, msg)
    if msg.type == "join" then
        if game.phase ~= "lobby" then
            sendTo(senderID, {type="error", msg="Game is in progress."})
            return
        end
        if #game.players >= MAX_PLAYERS then
            sendTo(senderID, {type="error", msg="Table is full."}); return
        end
        for _, p in ipairs(game.players) do
            if p.id == senderID then
                sendTo(senderID, {type="joined", name=p.name,
                    playerID=#game.players, dealerID=os.getComputerID()})
                return
            end
        end
        local name = (msg.name or "Player"):sub(1,14):match("^%s*(.-)%s*$")
        if name == "" then name = "Player" .. (#game.players+1) end
        local balance = math.max(100, math.min(10000, tonumber(msg.balance) or 1000))
        game.players[#game.players+1] = {
            id=senderID, name=name, hand={},
            balance=balance, roundBet=0, totalBet=0,
            folded=false, allIn=false, acted=false,
        }
        sendTo(senderID, {
            type="joined", name=name,
            playerID=#game.players, dealerID=os.getComputerID(), balance=balance,
        })

    elseif msg.type == "action" then
        handleAction(senderID, msg)

    elseif msg.type == "leave" then
        local wasCurrentPlayer = false
        for i, p in ipairs(game.players) do
            if p.id == senderID then
                if game.betting and i == game.actionIdx then
                    wasCurrentPlayer = true
                end
                -- Adjust actionIdx if needed
                if i < game.actionIdx then
                    game.actionIdx = game.actionIdx - 1
                end
                table.remove(game.players, i)
                break
            end
        end
        -- If it was their turn, advance
        if wasCurrentPlayer and game.betting and #game.players > 0 then
            if game.actionIdx > #game.players then game.actionIdx = 1 end
            -- Check if the game can continue
            local n, last = countActive()
            if n <= 1 then
                if last then autoWin(last) end
            elseif isBettingDone() then
                checkAutoAdvance()
            else
                -- Find next non-folded player
                local found = false
                for _ = 1, #game.players do
                    local p = game.players[game.actionIdx]
                    if p and not p.folded and not p.allIn then found = true; break end
                    game.actionIdx = game.actionIdx % #game.players + 1
                end
                if found then notifyTurn() end
            end
        end
        broadcastState()

    elseif msg.type == "request_state" then
        sendTo(senderID, {
            type="state", phase=game.phase, community=game.community,
            pot=game.pot, currentBet=game.currentBet,
            currentPlayer=currentPlayerName(),
            playerData=playerDataList(), betting=game.betting,
        })
        for _, p in ipairs(game.players) do
            if p.id == senderID and p.hand and #p.hand > 0 then
                sendTo(senderID, {type="hand", cards=p.hand, playerName=p.name, phase=game.phase})
                if game.betting and game.players[game.actionIdx] and game.players[game.actionIdx].id == senderID then
                    notifyTurn()
                end
                break
            end
        end
    end
end

-- =====================================================
-- MAIN LOOP
-- =====================================================
drawTable()
drawTerminal()

while true do
    local event, a, b, c = os.pullEvent()

    if event == "key" and a == keys.enter then
        if game.phase == "lobby" and #game.players >= MIN_PLAYERS then
            startGame()
        elseif game.phase == "showdown" then
            resetLobby()
        end
        drawTable()
        drawTerminal()

    elseif event == "rednet_message" then
        local senderID, rawMsg, protocol = a, b, c
        if protocol == PROTOCOL then
            local ok2, msg = pcall(textutils.unserialize, rawMsg)
            if ok2 and type(msg) == "table" then
                handlePlayerMsg(senderID, msg)
                drawTable()
                drawTerminal()
            end
        end
    end
end
