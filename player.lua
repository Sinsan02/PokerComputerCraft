-- player.lua
-- Texas Hold'em Spiller (lomme-PC)
-- Taster: C=Check/Call  R=Raise  F=Fold  A=All-in  Q=Avslutt

local dir   = fs.getDir(shell.getRunningProgram())
local cards = dofile(fs.combine(dir, "cards.lua"))

local PROTOCOL = "txpoker"

-- =====================================================
-- TRÅDLØS MODEM
-- =====================================================
local modemSide
for _, side in ipairs({"back","left","right","top","bottom","front"}) do
    local t = peripheral.getType(side)
    if t == "modem" then
        local p = peripheral.wrap(side)
        if p.isWireless and p.isWireless() then modemSide = side; break end
    end
end
if not modemSide then
    local found = peripheral.find("modem", function(_, p) return p.isWireless and p.isWireless() end)
    if found then modemSide = peripheral.getName(found) end
end
if not modemSide then
    print("FEIL: Ingen trådløs modem!"); return
end
rednet.open(modemSide)

-- =====================================================
-- OPPSTART - NAVN OG BALANSE
-- =====================================================
term.setBackgroundColor(colors.black)
term.setTextColor(colors.yellow)
term.clear(); term.setCursorPos(1,1)
print("=== TEXAS HOLD'EM ===")
term.setTextColor(colors.white)
print("")
print("Navn:")
term.setTextColor(colors.cyan)
local playerName = read()
if not playerName or playerName:match("^%s*$") then
    playerName = "Spiller" .. os.getComputerID()
end
playerName = playerName:sub(1,14):match("^%s*(.-)%s*$") or playerName

term.setTextColor(colors.white)
print("Start-balanse (100-10000):")
term.setTextColor(colors.cyan)
local balInput   = tonumber(read()) or 1000
local startBal   = math.max(100, math.min(10000, balInput))

-- =====================================================
-- TILSTAND
-- =====================================================
local st = {
    joined      = false,
    dealerID    = nil,
    name        = playerName,
    hand        = {},
    community   = {},
    pot         = 0,
    currentBet  = 0,
    myRoundBet  = 0,
    myBalance   = startBal,
    myTurn      = false,
    raising     = false,
    raiseBuffer = "",
    canCheck    = false,
    callAmount  = 0,
    minRaise    = 10,
    phase       = "lobby",
    winner      = nil,
    winHand     = nil,
    playerData  = {},
    currentPlayer = nil,
    betting     = false,
    msg         = "Kobler til...",
}

local W, H = term.getSize()

-- =====================================================
-- TEGNING
-- =====================================================
local function writeCard(c)
    term.setBackgroundColor(colors.white)
    term.setTextColor(colors.black)
    term.write("[")
    term.setTextColor(cards.CLR[c.suit])
    term.write(c.value .. cards.SYM[c.suit])
    term.setTextColor(colors.black)
    term.write("]")
    term.setBackgroundColor(colors.black)
    term.write(" ")
end

local function hline(y, clr)
    term.setCursorPos(1, y)
    term.setTextColor(clr or colors.gray)
    term.setBackgroundColor(colors.black)
    term.write(string.rep("-", W))
end

local function drawScreen()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Rad 1: Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.yellow)
    local hdr = " POKER - " .. st.name .. " "
    term.write(string.format("%-" .. W .. "s", hdr):sub(1, W))
    term.setBackgroundColor(colors.black)

    -- Rad 2: Fase og tur
    term.setCursorPos(1, 2)
    if st.myTurn then
        term.setTextColor(colors.yellow)
        term.write("*** DIN TUR ***")
    else
        term.setTextColor(colors.lightGray)
        local info = "Fase: " .. st.phase:upper()
        if st.betting and st.currentPlayer and not st.myTurn then
            info = info .. " | Tur: " .. st.currentPlayer
        end
        term.write(info:sub(1, W))
    end

    hline(3)

    -- Rad 4-5: Din hånd
    term.setCursorPos(1, 4)
    term.setTextColor(colors.white)
    term.write("DIN HAND:")
    term.setCursorPos(1, 5)
    if #st.hand == 0 then
        term.setTextColor(colors.gray); term.write("Venter på kort...")
    else
        for _, c in ipairs(st.hand) do writeCard(c) end
    end

    hline(6)

    -- Rad 7-8: Bordkort
    term.setCursorPos(1, 7)
    term.setTextColor(colors.white)
    term.write("BORD:")
    term.setCursorPos(1, 8)
    if #st.community == 0 then
        term.setTextColor(colors.gray); term.write("Ikke delt ennå")
    else
        for _, c in ipairs(st.community) do writeCard(c) end
    end

    hline(9)

    -- Rad 10-11: Pott og balanse
    term.setCursorPos(1, 10)
    term.setTextColor(colors.yellow)
    term.write(string.format("Pott: $%-5d  Bet: $%d", st.pot, st.currentBet):sub(1,W))
    term.setCursorPos(1, 11)
    term.setTextColor(colors.white)
    term.write(string.format("Balanse: $%-5d  Din bet: $%d", st.myBalance, st.myRoundBet):sub(1,W))

    hline(12)

    -- Rad 13+: Handlinger eller venter
    if st.myTurn then
        term.setCursorPos(1, 13)
        term.setTextColor(colors.cyan)
        if st.canCheck then
            term.write("[C]heck  [R]aise  [F]old")
        else
            term.write(string.format("[C]all $%d  [R]aise  [F]old", st.callAmount):sub(1,W))
        end
        term.setCursorPos(1, 14)
        term.setTextColor(colors.lightGray)
        term.write("[A]ll-in ($" .. st.myBalance .. ")")
    elseif st.phase == "showdown" and st.winner then
        hline(13, colors.yellow)
        term.setCursorPos(1, 14)
        if st.winner == st.name or st.winner:find(st.name) then
            term.setTextColor(colors.yellow)
            term.write("DU VANT! " .. (st.winHand or ""))
        else
            term.setTextColor(colors.white)
            term.write(("Vinner: " .. st.winner):sub(1,W))
            term.setCursorPos(1, 15)
            term.setTextColor(colors.lightGray)
            term.write((st.winHand or ""):sub(1,W))
        end
    elseif st.phase == "lobby" then
        term.setCursorPos(1, 13)
        term.setTextColor(colors.gray)
        term.write("Venter på at dealer starter...")
    else
        term.setCursorPos(1, 13)
        term.setTextColor(colors.gray)
        local wt = st.currentPlayer and ("Venter på: " .. st.currentPlayer) or "Venter..."
        term.write(wt:sub(1,W))
    end

    -- Spillerliste (kompakt, siste rader)
    local listStart = 16
    if #st.playerData > 0 and H >= listStart + 1 then
        hline(listStart - 1)
        for i, pd in ipairs(st.playerData) do
            if listStart + i - 1 > H - 1 then break end
            term.setCursorPos(1, listStart + i - 1)
            local isMe = pd.name == st.name
            local isCur = pd.name == st.currentPlayer
            if isCur then term.setTextColor(colors.cyan)
            elseif isMe then term.setTextColor(colors.yellow)
            elseif pd.folded then term.setTextColor(colors.gray)
            else term.setTextColor(colors.white)
            end
            local status = pd.folded and "F" or (pd.allIn and "AI" or "")
            term.write(string.format("%-9s $%-5d %s", pd.name:sub(1,9), pd.balance, status):sub(1,W))
        end
    end

    -- Raise-input prompt
    if st.raising then
        term.setCursorPos(1, H)
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.yellow)
        term.clearLine()
        term.write("Raise $: " .. st.raiseBuffer .. "_")
        return
    end

    -- Statuslinje nederst
    term.setCursorPos(1, H)
    term.setTextColor(colors.gray)
    term.setBackgroundColor(colors.black)
    term.write(string.format("%-" .. W .. "s", (st.msg or "")):sub(1,W))
end

-- =====================================================
-- SENDE HANDLINGER
-- =====================================================
local function sendAction(action, amount)
    if not st.dealerID then return end
    local m = {type="action", action=action}
    if amount then m.amount = amount end
    rednet.send(st.dealerID, textutils.serialize(m), PROTOCOL)
end

-- =====================================================
-- MELDINGSHÅNDTERING
-- =====================================================
local function handleMsg(senderID, msg)
    local fromDealer = (st.dealerID == nil) or (senderID == st.dealerID)

    if msg.type == "joined" and not st.joined then
        st.dealerID  = senderID
        st.joined    = true
        st.name      = msg.name or playerName
        st.myBalance = msg.balance or startBal
        st.phase     = "lobby"
        st.msg       = "Ble med! Venter på start..."

    elseif not fromDealer then return

    elseif msg.type == "error" then
        st.msg = "FEIL: " .. (msg.msg or "")

    elseif msg.type == "hand" then
        st.hand  = msg.cards or {}
        st.phase = msg.phase or st.phase
        st.msg   = "Kort mottatt! Sjekk hånden din."

    elseif msg.type == "state" then
        st.phase         = msg.phase or st.phase
        st.community     = msg.community or {}
        st.pot           = msg.pot or 0
        st.currentBet    = msg.currentBet or 0
        st.currentPlayer = msg.currentPlayer
        st.betting       = msg.betting or false
        st.playerData    = msg.playerData or {}
        st.winner        = nil
        -- Ikke nullstill myTurn om det er vår tur (your_turn kom like før state)
        if msg.currentPlayer ~= st.name then
            st.myTurn = false
        end
        -- Oppdater min balanse fra playerData
        for _, pd in ipairs(st.playerData) do
            if pd.name == st.name then
                st.myBalance  = pd.balance
                st.myRoundBet = pd.roundBet
                break
            end
        end
        local phMsgs = {deal="Kort er delt ut!", flop="Flop!", turn="Turn!", river="River - siste kort!"}
        st.msg = phMsgs[st.phase] or ""

    elseif msg.type == "your_turn" then
        st.myTurn      = true
        st.canCheck    = msg.canCheck or false
        st.callAmount  = msg.callAmount or 0
        st.currentBet  = msg.currentBet or 0
        st.myRoundBet  = msg.roundBet or 0
        st.myBalance   = msg.balance or st.myBalance
        st.pot         = msg.pot or st.pot
        st.minRaise    = msg.minRaise or 10
        st.msg         = "DIN TUR! Velg handling."

    elseif msg.type == "showdown" then
        st.phase      = "showdown"
        st.community  = msg.community or {}
        st.playerData = msg.playerData or {}
        st.winHand    = msg.winHand
        st.myTurn     = false
        st.betting    = false
        if msg.winners and #msg.winners > 0 then
            st.winner = table.concat(msg.winners, " & ")
            local iWon = false
            for _, w in ipairs(msg.winners) do
                if w == st.name then iWon = true; break end
            end
            st.msg = iWon and "Du vant!" or ("Vinner: " .. st.winner)
        end
        for _, pd in ipairs(st.playerData) do
            if pd.name == st.name then
                st.myBalance  = pd.balance
                st.myRoundBet = pd.roundBet
                break
            end
        end

    elseif msg.type == "lobby" then
        st.phase      = "lobby"
        st.hand       = {}
        st.community  = {}
        st.pot        = 0
        st.currentBet = 0
        st.myRoundBet = 0
        st.winner     = nil
        st.myTurn     = false
        st.betting    = false
        st.playerData = msg.playerData or {}
        for _, pd in ipairs(st.playerData) do
            if pd.name == st.name then st.myBalance = pd.balance; break end
        end
        st.msg = "Ny runde. Venter på dealer..."
        rednet.broadcast(textutils.serialize({
            type="join", name=playerName, balance=st.myBalance
        }), PROTOCOL)
    end
end

-- =====================================================
-- KOBLE TIL
-- =====================================================
st.msg = "Sender forespørsel..."
drawScreen()
rednet.broadcast(textutils.serialize({
    type="join", name=playerName, balance=startBal
}), PROTOCOL)

-- =====================================================
-- HOVED-LØKKE
-- =====================================================
local joinTimer = os.startTimer(3)
local retries   = 0

while true do
    local event, a, b, c = os.pullEvent()

    if event == "char" and st.raising then
        if a:match("%d") then
            st.raiseBuffer = st.raiseBuffer .. a
            drawScreen()
        end

    elseif event == "key" and st.raising then
        if a == keys.enter then
            local amt = tonumber(st.raiseBuffer)
            st.raising     = false
            st.raiseBuffer = ""
            if amt and amt >= st.minRaise then
                sendAction("raise", amt)
                st.myTurn = false
                st.msg    = "Du raised $" .. amt
            else
                st.msg = "Ugyldig (min $" .. st.minRaise .. ")"
            end
            drawScreen()
        elseif a == keys.backspace then
            st.raiseBuffer = st.raiseBuffer:sub(1, -2)
            drawScreen()
        elseif a == keys.q or a == keys.escape then
            st.raising     = false
            st.raiseBuffer = ""
            st.msg         = "Raise avbrutt"
            drawScreen()
        end

    elseif event == "rednet_message" then
        local sid, raw, proto = a, b, c
        if proto == PROTOCOL then
            local ok2, m = pcall(textutils.unserialize, raw)
            if ok2 and type(m) == "table" then
                handleMsg(sid, m)
                drawScreen()
            end
        end

    elseif event == "timer" and a == joinTimer then
        if not st.joined then
            retries = retries + 1
            st.msg  = "Prøver igjen... (" .. retries .. ")"
            rednet.broadcast(textutils.serialize({
                type="join", name=playerName, balance=startBal
            }), PROTOCOL)
            drawScreen()
            joinTimer = os.startTimer(3)
        end

    elseif event == "key" then
        local k = a

        if k == keys.q then
            if st.dealerID then
                rednet.send(st.dealerID, textutils.serialize({type="leave"}), PROTOCOL)
            end
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clear(); term.setCursorPos(1,1)
            print("Ha det!"); return

        elseif st.myTurn then
            if k == keys.c then
                -- Check eller Call
                if st.canCheck then
                    sendAction("check")
                else
                    sendAction("call")
                end
                st.myTurn = false
                st.msg    = st.canCheck and "Du sjekket." or ("Du calte $" .. st.callAmount)
                drawScreen()

            elseif k == keys.f then
                sendAction("fold")
                st.myTurn = false
                st.msg    = "Du foldet."
                drawScreen()

            elseif k == keys.a then
                sendAction("allin")
                st.myTurn = false
                st.msg    = "All-in! $" .. st.myBalance
                drawScreen()

            elseif k == keys.r then
                st.raising     = true
                st.raiseBuffer = ""
                drawScreen()
            end
        end
    end
end
