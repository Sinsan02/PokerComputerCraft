-- poker/player.lua
-- Texas Hold'em Spiller-program
-- Kjøres på lomme-PC (pocket computer) eller hvilken som helst PC med trådløs modem
-- Private kort vises kun her!

local dir   = fs.getDir(shell.getRunningProgram())
local cards = dofile(fs.combine(dir, "cards.lua"))

local PROTOCOL = "txpoker"

-- =====================================================
-- FINN TRÅDLØS MODEM
-- =====================================================
local modemSide = nil
local sides = {"back","left","right","top","bottom","front"}
for _, side in ipairs(sides) do
    if peripheral.getType(side) == "modem" then
        local p = peripheral.wrap(side)
        if p.isWireless and p.isWireless() then
            modemSide = side
            break
        end
    end
end
if not modemSide then
    -- Prøv peripheral.find som backup
    local found, foundName = peripheral.find("modem", function(n, p)
        return p.isWireless and p.isWireless()
    end)
    if found then modemSide = peripheral.getName(found) end
end

if not modemSide then
    print("FEIL: Ingen trådløs modem funnet!")
    print("Pocket-PCer har innebygd modem på 'back'.")
    print("Vanlige PCer: koble til trådløs modem.")
    return
end
rednet.open(modemSide)

-- =====================================================
-- SPILLER-NAVN
-- =====================================================
term.setBackgroundColor(colors.black)
term.setTextColor(colors.yellow)
term.clear()
term.setCursorPos(1, 1)
print("=== TEXAS HOLD'EM POKER ===")
term.setTextColor(colors.white)
print("")
print("Skriv inn ditt navn:")
term.setTextColor(colors.cyan)
local playerName = read()
if not playerName or playerName:match("^%s*$") then
    playerName = "Spiller" .. os.getComputerID()
end
playerName = playerName:sub(1, 14):match("^%s*(.-)%s*$") or playerName

-- =====================================================
-- SPILLTILSTAND
-- =====================================================
local state = {
    joined      = false,
    dealerID    = nil,
    playerName  = playerName,
    hand        = {},
    community   = {},
    pot         = 0,
    phase       = "lobby",
    winner      = nil,
    winHand     = nil,
    players     = {},
    message     = "Kobler til dealer...",
}

-- =====================================================
-- SKJERMTEGNING
-- =====================================================
local W, H = term.getSize()

-- Tegn et kort inline som  [A♥] med farge
local function writeCard(c)
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)
    term.write("[")
    term.setTextColor(cards.CLR[c.suit])
    -- Pad verdi til 2 tegn
    local valStr = c.value
    if #valStr == 1 then valStr = valStr .. " " end
    term.write(valStr .. cards.SYM[c.suit])
    term.setTextColor(colors.black)
    term.write("]")
    term.setBackgroundColor(colors.black)
    term.write(" ")
end

local function hline(y, char, clr)
    term.setCursorPos(1, y)
    term.setTextColor(clr or colors.gray)
    term.setBackgroundColor(colors.black)
    term.write(string.rep(char or "-", W))
end

local function cls()
    term.setBackgroundColor(colors.black)
    term.clear()
end

local function at(x, y)
    term.setCursorPos(x, y)
end

local function drawScreen()
    cls()

    -- Header
    at(1, 1)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.yellow)
    local header = " POKER - " .. state.playerName .. " "
    local padded = string.format("%-" .. W .. "s", header)
    term.write(padded:sub(1, W))
    term.setBackgroundColor(colors.black)

    -- Fase
    at(1, 2)
    term.setTextColor(colors.lightGray)
    local phaseStr = "Fase: " .. state.phase:upper()
    if state.dealerID then
        phaseStr = phaseStr .. "  |  Dealer: #" .. state.dealerID
    end
    term.write(phaseStr)

    hline(3, "-", colors.gray)

    -- Din hånd (private kort)
    at(1, 4)
    term.setTextColor(colors.white)
    term.write("DIN HÅND (privat):")

    at(1, 5)
    if #state.hand == 0 then
        term.setTextColor(colors.gray)
        term.write("[Ingen kort ennå]")
    else
        for _, c in ipairs(state.hand) do
            writeCard(c)
        end
    end

    hline(7, "-", colors.gray)

    -- Bordkort (community)
    at(1, 8)
    term.setTextColor(colors.white)
    term.write("BORDKORT:")

    at(1, 9)
    if #state.community == 0 then
        term.setTextColor(colors.gray)
        if state.phase == "lobby" or state.phase == "deal" then
            term.write("[Ikke delt ut ennå]")
        else
            term.write("[Ingen kort]")
        end
    else
        for _, c in ipairs(state.community) do
            writeCard(c)
        end
    end

    hline(11, "-", colors.gray)

    -- Info-rad
    at(1, 12)
    term.setTextColor(colors.yellow)
    term.write("Pott: " .. state.pot)

    -- Spillerliste
    if #state.players > 0 then
        at(1, 13)
        term.setTextColor(colors.lightGray)
        local pList = "Spillere: " .. table.concat(state.players, ", ")
        if #pList > W then pList = pList:sub(1, W - 3) .. "..." end
        term.write(pList)
    end

    -- Vinner
    if state.winner then
        hline(H - 3, "=", colors.yellow)
        at(1, H - 2)
        term.setTextColor(colors.yellow)
        local wStr = "VINNER: " .. state.winner
        if #wStr > W then wStr = wStr:sub(1, W) end
        term.write(wStr)
        at(1, H - 1)
        term.setTextColor(colors.white)
        local hStr = "  " .. (state.winHand or "")
        if #hStr > W then hStr = hStr:sub(1, W) end
        term.write(hStr)
    end

    -- Statusmelding nederst
    at(1, H)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.gray)
    local msg = state.message or ""
    if #msg > W then msg = msg:sub(1, W) end
    term.write(string.format("%-" .. W .. "s", msg))
end

local function setMsg(m)
    state.message = m
end

-- =====================================================
-- MELDINGSHÅNDTERING
-- =====================================================
local function handleMsg(senderID, msg)
    local fromDealer = (state.dealerID == nil) or (senderID == state.dealerID)

    if msg.type == "joined" and not state.joined then
        state.dealerID   = senderID
        state.joined     = true
        state.playerName = msg.name or playerName
        state.phase      = "lobby"
        setMsg("Ble med som spiller #" .. (msg.playerID or "?") .. ". Venter pa start...")

    elseif not fromDealer then
        -- Ignorer meldinger fra andre enn dealer etter join
        return

    elseif msg.type == "error" then
        setMsg("FEIL: " .. (msg.msg or "Ukjent feil"))

    elseif msg.type == "hand" then
        state.hand  = msg.cards or {}
        state.phase = msg.phase or state.phase
        setMsg("Du har fatt kortene dine! Se over.")

    elseif msg.type == "state" then
        state.phase     = msg.phase or state.phase
        state.community = msg.community or {}
        state.pot       = msg.pot or 0
        state.players   = msg.players or {}
        state.winner    = nil
        state.winHand   = nil

        local msgs = {
            deal  = "Kort er delt. Sjekk handen din!",
            flop  = "Flop er vist - 3 bordkort.",
            turn  = "Turn - 4. bordkort er vist.",
            river = "River - siste bordkort. Klar for showdown?",
        }
        setMsg(msgs[state.phase] or "")

    elseif msg.type == "showdown" then
        state.phase     = "showdown"
        state.community = msg.community or {}
        state.players   = msg.players or {}
        state.winHand   = msg.winHand

        if msg.winners and #msg.winners > 0 then
            state.winner = table.concat(msg.winners, " & ")
            if #msg.winners > 1 then
                state.winner = state.winner .. " (Uavgjort!)"
            end
            -- Sjekk om vi vant
            for _, wName in ipairs(msg.winners) do
                if wName == state.playerName then
                    setMsg("Du VANT runden! Gratulerer!")
                    break
                else
                    setMsg("Vinner: " .. state.winner)
                end
            end
        else
            setMsg("Showdown!")
        end

    elseif msg.type == "lobby" then
        state.phase     = "lobby"
        state.hand      = {}
        state.community = {}
        state.pot       = 0
        state.winner    = nil
        state.winHand   = nil
        state.players   = msg.players or {}
        setMsg("Ny runde starter snart. Venter...")
        -- Meld på igjen
        rednet.broadcast(textutils.serialize({type="join", name=playerName}), PROTOCOL)
    end
end

-- =====================================================
-- KOBLE TIL DEALER
-- =====================================================
setMsg("Sender koblings-forspørsel...")
drawScreen()
rednet.broadcast(textutils.serialize({type="join", name=playerName}), PROTOCOL)

-- =====================================================
-- HOVED-LØKKE
-- =====================================================
local joinTimer    = os.startTimer(3)   -- prøv å koble til igjen etter 3 sek
local retryCount   = 0

while true do
    local event, a, b, c = os.pullEvent()

    if event == "rednet_message" then
        local senderID, rawMsg, protocol = a, b, c
        if protocol == PROTOCOL then
            local ok, msg = pcall(textutils.unserialize, rawMsg)
            if ok and type(msg) == "table" then
                handleMsg(senderID, msg)
                drawScreen()
            end
        end

    elseif event == "timer" and a == joinTimer then
        if not state.joined then
            retryCount = retryCount + 1
            setMsg("Prøver å koble til... (" .. retryCount .. ")")
            rednet.broadcast(textutils.serialize({type="join", name=playerName}), PROTOCOL)
            drawScreen()
            joinTimer = os.startTimer(3)
        else
            -- Spør om tilstand ved koble-til på nytt
            if state.dealerID then
                rednet.send(state.dealerID,
                    textutils.serialize({type="request_state"}), PROTOCOL)
            end
        end

    elseif event == "key" then
        -- Trykk R for å be om oppdatert tilstand
        if a == keys.r and state.dealerID then
            rednet.send(state.dealerID,
                textutils.serialize({type="request_state"}), PROTOCOL)
            setMsg("Ber om oppdatering...")
            drawScreen()
        end
        -- Trykk Q for å forlate
        if a == keys.q then
            if state.dealerID then
                rednet.send(state.dealerID,
                    textutils.serialize({type="leave"}), PROTOCOL)
            end
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clear()
            term.setCursorPos(1,1)
            print("Du har forlatt spillet. Ha det!")
            return
        end
    end
end
