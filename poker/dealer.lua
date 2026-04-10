-- dealer.lua
-- Texas Hold'em Dealer with betting
-- Dealer presses ENTER to start a round and to start a new round after showdown
-- Everything else (flop/turn/river/showdown) happens automatically when all players have acted

local dir   = fs.getDir(shell.getRunningProgram())
local cards = dofile(fs.combine(dir, "cards.lua"))
local eval  = dofile(fs.combine(dir, "eval.lua"))

local PROTOCOL   = "txpoker"
local MIN_PLAYERS = 2
local MAX_PLAYERS = 8
local MIN_RAISE   = 10

-- =====================================================
-- PERIPHERALS
-- =====================================================
local mon = peripheral.find("monitor")
if not mon then
    print("ERROR: No monitor found!"); return
end
mon.setTextScale(1)

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
-- MONITOR DRAWING
-- =====================================================
local function mfill(x1, y1, x2, y2, char, bg)
    mon.setBackgroundColor(bg or colors.green)
    local row = string.rep(char or " ", x2 - x1 + 1)
    for y = y1, y2 do mon.setCursorPos(x1, y); mon.write(row) end
end

local function drawMonCard(mx, my, card)
    if not card then
        mon.setBackgroundColor(colors.green)
        mon.setTextColor(colors.lime)
        local empty = {"+---+", "|   |", "|   |", "|   |", "+---+"}
        for dy, row in ipairs(empty) do
            mon.setCursorPos(mx, my + dy - 1); mon.write(row)
        end
        return
    end
    local sClr = cards.CLR[card.suit]
    mon.setBackgroundColor(colors.white)
    mon.setTextColor(colors.black)
    mon.setCursorPos(mx, my);     mon.write("+---+")
    mon.setCursorPos(mx, my + 1); mon.write("|   |")
    mon.setCursorPos(mx + 1, my + 1)
    mon.setTextColor(sClr); mon.write(card.value)
    mon.setCursorPos(mx, my + 2)
    mon.setTextColor(colors.black); mon.write("|   |")
    mon.setCursorPos(mx, my + 3); mon.write("|   |")
    mon.setCursorPos(mx + 3, my + 3)
    mon.setTextColor(sClr); mon.write(cards.SYM[card.suit])
    mon.setCursorPos(mx, my + 4)
    mon.setTextColor(colors.black); mon.write("+---+")
end

local function drawTable()
    local W, H = mon.getSize()
    mfill(1, 1, W, H, " ", colors.green)

    -- Title
    local title = "=== TEXAS HOLD'EM POKER ==="
    mon.setCursorPos(math.floor((W - #title) / 2) + 1, 1)
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.yellow)
    mon.write(title)

    -- Phase
    local phaseNames = {
        lobby="LOBBY", deal="CARDS DEALT",
        flop="FLOP", turn="TURN", river="RIVER", showdown="SHOWDOWN"
    }
    local phStr = "[ " .. (phaseNames[game.phase] or game.phase:upper()) .. " ]"
    if game.betting then
        phStr = phStr .. "  Turn: " .. (currentPlayerName() or "")
    end
    mon.setCursorPos(math.floor((W - #phStr) / 2) + 1, 2)
    mon.setTextColor(colors.white); mon.write(phStr)

    -- Community cards
    local cardW = 5; local cardH = 5; local spacing = 1
    local totalW = 5 * cardW + 4 * spacing
    local startX = math.floor((W - totalW) / 2) + 1
    local startY = 4
    for i = 1, 5 do
        drawMonCard(startX + (i-1)*(cardW+spacing), startY, game.community[i])
    end

    -- Pot and current bet
    local potStr = "Pot: $" .. game.pot
    if game.currentBet > 0 then
        potStr = potStr .. "  |  Current bet: $" .. game.currentBet
    end
    mon.setCursorPos(2, startY + cardH + 1)
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.yellow)
    mon.write(potStr)

    -- Player list with balance and bet
    local listY = startY + cardH + 2
    mon.setCursorPos(2, listY)
    mon.setTextColor(colors.lightGray)
    mon.write("Players:")

    for i, p in ipairs(game.players) do
        if listY + i > H - 2 then break end
        mon.setCursorPos(2, listY + i)

        local isCurrent = game.betting and (i == game.actionIdx)
        local status = ""
        if p.folded  then status = " [FOLD]"
        elseif p.allIn then status = " [ALL-IN]"
        end

        local handName = ""
        if game.phase == "showdown" then
            for _, r in ipairs(game.results) do
                if r.name == p.name then handName = " [" .. r.handName .. "]"; break end
            end
        end

        local pLine = string.format("%d. %-10s $%-5d bet:$%d%s%s",
            i, p.name, p.balance, p.roundBet, status, handName)
        if #pLine > W - 3 then pLine = pLine:sub(1, W - 3) end

        if game.winner and p.name == game.winner then
            mon.setTextColor(colors.yellow)
        elseif isCurrent then
            mon.setTextColor(colors.cyan)
        elseif p.folded then
            mon.setTextColor(colors.gray)
        else
            mon.setTextColor(colors.white)
        end

        mon.write(pLine)
        mon.setBackgroundColor(colors.green)
        local pad = W - 2 - #pLine
        if pad > 0 then mon.write(string.rep(" ", pad)) end
    end

    -- Winner banner
    if game.winner then
        local wStr = " WINNER: " .. game.winner .. " - " .. (game.winHand or "") .. " "
        if #wStr > W then wStr = wStr:sub(1, W) end
        local wx = math.floor((W - #wStr) / 2) + 1
        mon.setCursorPos(wx, H - 1)
        mon.setBackgroundColor(colors.yellow)
        mon.setTextColor(colors.black)
        mon.write(wStr)
        mon.setBackgroundColor(colors.green)
    end

    mon.setCursorPos(W - 14, H)
    mon.setTextColor(colors.gray)
    mon.write("Dealer ID: " .. os.getComputerID())
end

-- =====================================================
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
