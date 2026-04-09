-- poker/dealer.lua
-- Texas Hold'em Dealer
-- Krav: Monitor koblet til + trådløs modem installert
-- Kontroll: ENTER = neste fase

local dir   = fs.getDir(shell.getRunningProgram())
local cards = dofile(fs.combine(dir, "cards.lua"))
local eval  = dofile(fs.combine(dir, "eval.lua"))

local PROTOCOL = "txpoker"
local MIN_PLAYERS = 2
local MAX_PLAYERS = 8

-- =====================================================
-- FINN PERIFERIUTSTYR
-- =====================================================
local mon = peripheral.find("monitor")
if not mon then
    print("FEIL: Ingen monitor funnet!")
    print("Koble til en monitor og start på nytt.")
    return
end
mon.setTextScale(1)

local modemName
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
        local p = peripheral.wrap(name)
        if p.isWireless and p.isWireless() then
            modemName = name
            break
        end
    end
end
if not modemName then
    print("FEIL: Ingen trådløs modem funnet!")
    return
end
rednet.open(modemName)

-- =====================================================
-- SPILLTILSTAND
-- =====================================================
local game = {
    phase     = "lobby",
    deck      = {},
    community = {},
    players   = {},   -- {id, name, hand={}, active=true}
    pot       = 0,
    winner    = nil,
    winHand   = nil,
    results   = {},   -- showdown-resultater
}

-- =====================================================
-- MONITOR-TEGNING (BORD)
-- =====================================================
local function mfill(x1, y1, x2, y2, char, bg)
    mon.setBackgroundColor(bg or colors.green)
    local row = string.rep(char or " ", x2 - x1 + 1)
    for y = y1, y2 do
        mon.setCursorPos(x1, y)
        mon.write(row)
    end
end

-- Tegn ett kort på monitor (5 bred x 5 høy)
-- +---+
-- |V  |
-- |   |
-- |  S|
-- +---+
local function drawMonCard(mx, my, card)
    if not card then
        -- Tom slot med stiplede kanter
        mon.setBackgroundColor(colors.green)
        mon.setTextColor(colors.lime)
        local rows = {"+---+", "|   |", "|   |", "|   |", "+---+"}
        for dy, row in ipairs(rows) do
            mon.setCursorPos(mx, my + dy - 1)
            mon.write(row)
        end
        return
    end

    local sClr = cards.CLR[card.suit]
    local sym  = cards.SYM[card.suit]
    local val  = card.value

    -- Bakgrunn hvit
    mon.setBackgroundColor(colors.white)
    mon.setTextColor(colors.black)

    -- Topp kant
    mon.setCursorPos(mx, my);     mon.write("+---+")
    -- Verdi-rad
    mon.setCursorPos(mx, my + 1); mon.write("|   |")
    mon.setCursorPos(mx + 1, my + 1)
    mon.setTextColor(sClr)
    mon.write(val)
    -- Midtrad
    mon.setCursorPos(mx, my + 2)
    mon.setTextColor(colors.black)
    mon.write("|   |")
    -- Suit-rad
    mon.setCursorPos(mx, my + 3); mon.write("|   |")
    mon.setCursorPos(mx + 3, my + 3)
    mon.setTextColor(sClr)
    mon.write(sym)
    -- Bunn kant
    mon.setCursorPos(mx, my + 4)
    mon.setTextColor(colors.black)
    mon.write("+---+")
end

local function drawTable()
    local W, H = mon.getSize()

    -- Grønn filt-bakgrunn
    mfill(1, 1, W, H, " ", colors.green)

    -- Tittel
    local title = "=== TEXAS HOLD'EM POKER ==="
    mon.setCursorPos(math.max(1, math.floor((W - #title) / 2) + 1), 1)
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.yellow)
    mon.write(title)

    -- Fase
    local phaseNames = {
        lobby    = "LOBBY - Venter pa spillere",
        deal     = "KORT DELT UT",
        flop     = "FLOP",
        turn     = "TURN",
        river    = "RIVER",
        showdown = "SHOWDOWN",
    }
    local phStr = "[ " .. (phaseNames[game.phase] or game.phase:upper()) .. " ]"
    mon.setCursorPos(math.max(1, math.floor((W - #phStr) / 2) + 1), 2)
    mon.setTextColor(colors.white)
    mon.write(phStr)

    -- Bordkort (5 kort, hver 5 bred med 1 mellomrom -> totalt 29)
    local cardW    = 5
    local cardH    = 5
    local spacing  = 1
    local totalW   = 5 * cardW + 4 * spacing  -- 29
    local startX   = math.max(1, math.floor((W - totalW) / 2) + 1)
    local startY   = 4

    for i = 1, 5 do
        local cx = startX + (i - 1) * (cardW + spacing)
        drawMonCard(cx, startY, game.community[i])
    end

    -- Bordkort-etikett
    mon.setBackgroundColor(colors.green)
    mon.setTextColor(colors.lightGray)
    local lbl = "Bordkort"
    mon.setCursorPos(math.floor((W - #lbl) / 2) + 1, startY + cardH)
    mon.write(lbl)

    -- Pott
    local potStr = "Pott: " .. game.pot .. " kr"
    mon.setCursorPos(2, startY + cardH + 1)
    mon.setTextColor(colors.yellow)
    mon.write(potStr)

    -- Antall spillere
    local pStr = "Spillere: " .. #game.players
    mon.setCursorPos(W - #pStr - 1, startY + cardH + 1)
    mon.setTextColor(colors.white)
    mon.write(pStr)

    -- Spillerliste
    local listY = startY + cardH + 2
    mon.setCursorPos(2, listY)
    mon.setTextColor(colors.lightGray)
    mon.write("Spillere:")

    for i, p in ipairs(game.players) do
        if listY + i > H - 2 then break end
        mon.setCursorPos(2, listY + i)

        local pLine = i .. ". " .. p.name

        if game.phase == "showdown" then
            -- Vis håndnavn ved showdown
            for _, r in ipairs(game.results) do
                if r.name == p.name then
                    pLine = pLine .. " [" .. r.handName .. "]"
                    break
                end
            end
        end

        -- Fremhev vinner
        if game.winner and p.name == game.winner then
            mon.setTextColor(colors.yellow)
        else
            mon.setTextColor(colors.white)
        end
        -- Klipp linje til bredden
        if #pLine > W - 3 then pLine = pLine:sub(1, W - 3) end
        mon.write(pLine)
        mon.setBackgroundColor(colors.green)
        -- Fyll resten av linjen
        local pad = W - 2 - #pLine
        if pad > 0 then mon.write(string.rep(" ", pad)) end
    end

    -- Vinner-banner
    if game.winner then
        local wStr = " VINNER: " .. game.winner .. " - " .. (game.winHand or "") .. " "
        local wx = math.max(1, math.floor((W - #wStr) / 2) + 1)
        mon.setCursorPos(wx, H - 1)
        mon.setBackgroundColor(colors.yellow)
        mon.setTextColor(colors.black)
        mon.write(wStr)
        mon.setBackgroundColor(colors.green)
    end

    -- Dealer-ID nederst til høyre
    mon.setCursorPos(W - 14, H)
    mon.setTextColor(colors.gray)
    mon.write("Dealer ID: " .. os.getComputerID())
end

-- =====================================================
-- TERMINAL (DEALER-SKJERM)
-- =====================================================
local function drawTerminal()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("=== POKER DEALER KONTROLL ===")
    term.setTextColor(colors.white)
    print("Fase: " .. game.phase:upper())
    print("Min ID: " .. os.getComputerID() .. " | Protokoll: " .. PROTOCOL)
    print(string.rep("-", 40))

    print("Spillere (" .. #game.players .. "):")
    for i, p in ipairs(game.players) do
        term.setTextColor(colors.lightGray)
        print(string.format("  %d. %-12s (ID: %d)", i, p.name, p.id))
    end

    term.setTextColor(colors.white)
    print(string.rep("-", 40))

    if game.phase == "lobby" then
        if #game.players < MIN_PLAYERS then
            term.setTextColor(colors.red)
            print("Venter pa minst " .. MIN_PLAYERS .. " spillere...")
        else
            term.setTextColor(colors.green)
            print("[ENTER] Start spill (" .. #game.players .. " spillere klare)")
        end
    elseif game.phase == "deal" then
        term.setTextColor(colors.cyan)
        print("[ENTER] Vis Flop (3 bordkort)")
    elseif game.phase == "flop" then
        term.setTextColor(colors.cyan)
        print("[ENTER] Vis Turn (4. bordkort)")
    elseif game.phase == "turn" then
        term.setTextColor(colors.cyan)
        print("[ENTER] Vis River (5. bordkort)")
    elseif game.phase == "river" then
        term.setTextColor(colors.cyan)
        print("[ENTER] Showdown - Se hvem som vinner!")
    elseif game.phase == "showdown" then
        if game.winner then
            term.setTextColor(colors.yellow)
            print("VINNER: " .. game.winner)
            print("HÅND: " .. (game.winHand or ""))
        end
        term.setTextColor(colors.green)
        print("[ENTER] Nytt spill (beholder spillere)")
    end
    term.setTextColor(colors.gray)
    print("")
    print("Spillere kobler til med player.lua")
end

-- =====================================================
-- NETTVERK
-- =====================================================
local function broadcast(msg)
    rednet.broadcast(textutils.serialize(msg), PROTOCOL)
end

local function sendTo(id, msg)
    rednet.send(id, textutils.serialize(msg), PROTOCOL)
end

local function getPlayerNames()
    local names = {}
    for _, p in ipairs(game.players) do names[#names + 1] = p.name end
    return names
end

-- =====================================================
-- SPILLOGIKK
-- =====================================================
local function startGame()
    game.deck      = cards.newDeck()
    cards.shuffle(game.deck)
    game.community = {}
    game.winner    = nil
    game.winHand   = nil
    game.results   = {}
    game.pot       = 0
    game.phase     = "deal"

    -- Del ut 2 kort til hver spiller
    for _, p in ipairs(game.players) do
        p.hand = {cards.deal(game.deck), cards.deal(game.deck)}
        sendTo(p.id, {
            type       = "hand",
            cards      = p.hand,
            playerName = p.name,
            phase      = "deal",
        })
    end

    broadcast({
        type      = "state",
        phase     = "deal",
        community = {},
        players   = getPlayerNames(),
        pot       = game.pot,
    })
end

local function doFlop()
    cards.deal(game.deck)  -- brent kort
    for _ = 1, 3 do
        game.community[#game.community + 1] = cards.deal(game.deck)
    end
    game.phase = "flop"
    broadcast({type="state", phase="flop", community=game.community,
               players=getPlayerNames(), pot=game.pot})
end

local function doTurn()
    cards.deal(game.deck)  -- brent kort
    game.community[#game.community + 1] = cards.deal(game.deck)
    game.phase = "turn"
    broadcast({type="state", phase="turn", community=game.community,
               players=getPlayerNames(), pot=game.pot})
end

local function doRiver()
    cards.deal(game.deck)  -- brent kort
    game.community[#game.community + 1] = cards.deal(game.deck)
    game.phase = "river"
    broadcast({type="state", phase="river", community=game.community,
               players=getPlayerNames(), pot=game.pot})
end

local function doShowdown()
    game.phase   = "showdown"
    game.results = {}

    local bestR, bestT = 0, {}
    local winners = {}

    for _, p in ipairs(game.players) do
        local allCards = {}
        for _, c in ipairs(p.hand)      do allCards[#allCards + 1] = c end
        for _, c in ipairs(game.community) do allCards[#allCards + 1] = c end

        local r, t, name = eval.best(allCards)
        game.results[#game.results + 1] = {
            name     = p.name,
            hand     = p.hand,
            handName = name,
            rank     = r,
            ties     = t,
        }

        local cmp = eval.compare(r, t, bestR, bestT)
        if cmp > 0 then
            bestR, bestT = r, t
            winners = {p.name}
        elseif cmp == 0 and #winners > 0 then
            winners[#winners + 1] = p.name
        end
    end

    if #winners == 1 then
        game.winner  = winners[1]
    elseif #winners > 1 then
        game.winner  = table.concat(winners, " & ") .. " (Uavgjort!)"
    else
        game.winner  = "Ingen"
    end

    -- Finn vinnerhånds navn
    for _, r in ipairs(game.results) do
        if r.name == winners[1] then
            game.winHand = r.handName
            break
        end
    end

    broadcast({
        type      = "showdown",
        community = game.community,
        results   = game.results,
        winners   = winners,
        winHand   = game.winHand,
        players   = getPlayerNames(),
        pot       = game.pot,
    })
end

local function resetLobby()
    game.phase     = "lobby"
    game.community = {}
    game.winner    = nil
    game.winHand   = nil
    game.results   = {}
    game.pot       = 0
    for _, p in ipairs(game.players) do p.hand = {} end
    broadcast({type = "lobby", players = getPlayerNames()})
end

local function advancePhase()
    if game.phase == "lobby" then
        if #game.players >= MIN_PLAYERS then
            startGame()
        end
    elseif game.phase == "deal"     then doFlop()
    elseif game.phase == "flop"     then doTurn()
    elseif game.phase == "turn"     then doRiver()
    elseif game.phase == "river"    then doShowdown()
    elseif game.phase == "showdown" then resetLobby()
    end
end

-- =====================================================
-- HANDLE SPILLER-MELDINGER
-- =====================================================
local function handlePlayerMsg(senderID, msg)
    if msg.type == "join" then
        if game.phase ~= "lobby" then
            sendTo(senderID, {type="error", msg="Spillet er i gang. Vent til neste runde."})
            return
        end
        if #game.players >= MAX_PLAYERS then
            sendTo(senderID, {type="error", msg="Fullt bord (maks " .. MAX_PLAYERS .. " spillere)."})
            return
        end

        -- Sjekk om allerede ble med
        for _, p in ipairs(game.players) do
            if p.id == senderID then
                sendTo(senderID, {type="joined", name=p.name,
                    playerID=#game.players, dealerID=os.getComputerID()})
                return
            end
        end

        local name = tostring(msg.name or ("Spiller" .. (#game.players + 1)))
        name = name:sub(1, 14)
        -- Unngå duplikate navn
        for _, p in ipairs(game.players) do
            if p.name:lower() == name:lower() then
                name = name .. (#game.players + 1)
                break
            end
        end

        game.players[#game.players + 1] = {id=senderID, name=name, hand={}, active=true}
        sendTo(senderID, {
            type     = "joined",
            name     = name,
            playerID = #game.players,
            dealerID = os.getComputerID(),
        })

    elseif msg.type == "leave" then
        for i, p in ipairs(game.players) do
            if p.id == senderID then
                table.remove(game.players, i)
                break
            end
        end

    elseif msg.type == "request_state" then
        sendTo(senderID, {
            type      = "state",
            phase     = game.phase,
            community = game.community,
            players   = getPlayerNames(),
            pot       = game.pot,
        })
        -- Send tilbake private kort om aktiv spiller
        for _, p in ipairs(game.players) do
            if p.id == senderID and p.hand and #p.hand > 0 then
                sendTo(senderID, {
                    type       = "hand",
                    cards      = p.hand,
                    playerName = p.name,
                    phase      = game.phase,
                })
                break
            end
        end
    end
end

-- =====================================================
-- HOVEDLØKKE
-- =====================================================
drawTable()
drawTerminal()

while true do
    local event, a, b, c = os.pullEvent()

    if event == "key" then
        if a == keys.enter then
            advancePhase()
            drawTable()
            drawTerminal()
        end

    elseif event == "rednet_message" then
        local senderID, rawMsg, protocol = a, b, c
        if protocol == PROTOCOL then
            local ok, msg = pcall(textutils.unserialize, rawMsg)
            if ok and type(msg) == "table" then
                handlePlayerMsg(senderID, msg)
                drawTable()
                drawTerminal()
            end
        end
    end
end
