-- roulette/table.lua
-- Casino Roulette — 4x4 monitor, spinning wheel dominates the screen
-- Requires: 4x4 monitor array + wireless modem + casino_db running

local PROTOCOL       = "roulette"
local CASINO_PROTO   = "casino"
local BET_SECONDS    = 25
local RESULT_SECONDS = 7
local CASINO_TIMEOUT = 3
local MIN_BET        = 1

-- ── Roulette numbers ──────────────────────────────────────────────
local WHEEL = {
    0,32,15,19,4,21,2,25,17,34,6,27,13,36,
    11,30,8,23,10,5,24,16,33,1,20,14,31,9,
    22,18,29,7,28,12,35,3,26
}
local WLEN = #WHEEL  -- 37

local RED = {}
for _, n in ipairs({1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36}) do
    RED[n] = true
end

local function numBg(n)
    if n == 0 then return colors.lime end
    if RED[n]  then return colors.red  end
    return colors.gray
end

local function wheelIdx(n)
    for i, v in ipairs(WHEEL) do if v == n then return i end end
    return 1
end

-- ── Peripherals ───────────────────────────────────────────────────
local mon = peripheral.find("monitor")
if not mon then print("ERROR: No monitor found!"); return end
mon.setTextScale(0.5)
local MW, MH = mon.getSize()

local modemName
for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
        local p = peripheral.wrap(name)
        if p.isWireless and p.isWireless() then modemName = name; break end
    end
end
if not modemName then print("ERROR: No wireless modem!"); return end
rednet.open(modemName)

-- ── Casino DB ────────────────────────────────────────────────────
local function casinoReq(msg)
    local sid = rednet.lookup(CASINO_PROTO)
    if not sid then return nil end
    rednet.send(sid, msg, CASINO_PROTO)
    local _, resp = rednet.receive(CASINO_PROTO, CASINO_TIMEOUT)
    return resp
end

local function updateChips(username, delta)
    if delta == 0 then return end
    casinoReq({type="update_chips", username=username, delta=delta})
end

local function getBalance(username)
    local resp = casinoReq({type="get_balance", username=username})
    return (resp and resp.ok) and resp.chips or nil
end

-- ── Game state ────────────────────────────────────────────────────
local game = {
    phase      = "waiting",
    players    = {},
    bets       = {},
    result     = nil,
    betLeft    = 0,
    betTimer   = nil,
    resTimer   = nil,
    payouts    = {},
    animFrames = {},
    animIdx    = 1,
    animTimer  = nil,
    animOffset = 1,
}

local function sendTo(id, msg)
    rednet.send(id, textutils.serialize(msg), PROTOCOL)
end

local function broadcast(msg)
    for id in pairs(game.players) do
        rednet.send(id, textutils.serialize(msg), PROTOCOL)
    end
end

-- ── Payout logic ──────────────────────────────────────────────────
local PAYOUTS = {
    number=35, red=1, black=1, even=1, odd=1,
    low=1, high=1, dozen1=2, dozen2=2, dozen3=2,
    col1=2, col2=2, col3=2,
}

local function betWins(btype, bvalue, res)
    if btype == "number"  then return bvalue == res
    elseif btype == "red"    then return res > 0 and RED[res]
    elseif btype == "black"  then return res > 0 and not RED[res]
    elseif btype == "even"   then return res > 0 and res % 2 == 0
    elseif btype == "odd"    then return res > 0 and res % 2 == 1
    elseif btype == "low"    then return res >= 1 and res <= 18
    elseif btype == "high"   then return res >= 19 and res <= 36
    elseif btype == "dozen1" then return res >= 1 and res <= 12
    elseif btype == "dozen2" then return res >= 13 and res <= 24
    elseif btype == "dozen3" then return res >= 25 and res <= 36
    elseif btype == "col1"   then return res > 0 and res % 3 == 1
    elseif btype == "col2"   then return res > 0 and res % 3 == 2
    elseif btype == "col3"   then return res > 0 and res % 3 == 0
    end
    return false
end

-- ── Animation ─────────────────────────────────────────────────────
local CW    = 6                          -- cell width
local BCELL = math.floor((MW / CW) / 2) -- ball cell index (0-based)

local function buildAnim(result)
    local rIdx      = wheelIdx(result)
    local targetOff = ((rIdx - BCELL - 1) % WLEN + WLEN) % WLEN + 1
    local startOff  = math.random(1, WLEN)

    local speeds = {}
    local function add(n, s) for i=1,n do speeds[#speeds+1] = s end end
    add(18, 5); add(18, 4); add(14, 3); add(14, 2); add(12, 1)

    local tot = 0
    for _, s in ipairs(speeds) do tot = tot + s end
    local endOff = ((startOff - 1 + tot) % WLEN + WLEN) % WLEN + 1
    local extra  = ((targetOff - endOff + WLEN) % WLEN)
    for i = 1, extra do speeds[#speeds+1] = 1 end
    speeds[#speeds+1] = 0
    speeds[#speeds+1] = 0

    local frames, pos = {startOff}, startOff
    for _, s in ipairs(speeds) do
        pos = ((pos - 1 + s) % WLEN + WLEN) % WLEN + 1
        frames[#frames+1] = pos
    end
    return frames
end

local ANIM_DELAYS = {}
do
    local function fill(a, b, c)
        for i = a, b do ANIM_DELAYS[i] = c end
    end
    fill(1,  18, 0.04)
    fill(19, 36, 0.07)
    fill(37, 50, 0.12)
    fill(51, 64, 0.20)
    fill(65, 999, 0.30)
end

-- ── Monitor helpers ───────────────────────────────────────────────
local function mset(x, y, bg, fg)
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(bg or colors.black)
    mon.setTextColor(fg or colors.white)
end

local function mfill(x1, y1, x2, y2, bg, ch)
    ch = ch or " "
    mon.setBackgroundColor(bg or colors.black)
    local row = string.rep(ch, x2 - x1 + 1)
    for y = y1, y2 do mon.setCursorPos(x1, y); mon.write(row) end
end

local function mwrite(x, y, text, bg, fg)
    mset(x, y, bg, fg)
    mon.write(text)
end

local function mwriteC(y, text, bg, fg, x1, x2)
    x1 = x1 or 1; x2 = x2 or MW
    local x = x1 + math.floor((x2 - x1 + 1 - #text) / 2)
    mwrite(x, y, text, bg, fg)
end

-- ── Layout constants ──────────────────────────────────────────────
-- Row 1:         title bar
-- Rows 2..MH-14: WHEEL (large, ~70% of height)
-- Row MH-13..MH-12: [gap]
-- Rows MH-12..MH-3: number grid (NUM_H=2, dozen, outside = 10 rows)
-- Row MH-2:      separator
-- Rows MH-1..MH: player list

local WY1  = 2
local WY2  = MH - 14
local WMID = math.floor((WY1 + WY2) / 2)

local GY        = WY2 + 2        -- number grid starts here
local NUM_ROWS  = 3
local NUM_COLS  = 12
local NUM_H     = 2               -- 2-row cells → double grid height
local ZERO_W    = 3
local COL_BET_W = 4
local NUM_W     = math.max(3, math.floor((MW - ZERO_W - COL_BET_W) / NUM_COLS))

-- ── Wheel ─────────────────────────────────────────────────────────
local AW = 5   -- arrow width (bold: 5 chars)
local AH = 5   -- arrow height (bold: 5 rows)

local function drawArrows(num)
    local bx = 1 + BCELL * CW
    local label = string.format("[%2d]", num)
    -- Left arrows: >>>>> pointing right toward ball cell
    if bx - AW - 1 >= 1 then
        for dy = -(AH//2), AH//2 do
            mwrite(bx - AW - 1, WMID + dy, string.rep(">", AW), colors.black, colors.yellow)
        end
    end
    -- Right arrows: <<<<< pointing left toward ball cell
    if bx + CW + AW - 1 <= MW then
        for dy = -(AH//2), AH//2 do
            mwrite(bx + CW, WMID + dy, string.rep("<", AW), colors.black, colors.yellow)
        end
    end
end

local function drawWheel(offset, stopped, stoppedNum)
    mfill(1, WY1, MW, WY2, colors.black)

    local cells = math.floor(MW / CW)
    for i = 0, cells - 1 do
        local wIdx   = ((offset - 1 + i) % WLEN + WLEN) % WLEN + 1
        local num    = WHEEL[wIdx]
        local bg     = numBg(num)
        local isBall = (i == BCELL)
        local x      = 1 + i * CW
        local x2     = x + CW - 2  -- right border gap

        -- All cells same structure: color block with black right gap
        mfill(x,          WY1, x2,          WY2, bg)
        mfill(x + CW - 1, WY1, x + CW - 1, WY2, colors.black)

        if isBall then
            -- Ball cell: normal color but number in yellow for contrast
            mwriteC(WMID, string.format("%2d", num), bg, colors.yellow, x, x2)
        else
            mwriteC(WMID, string.format("%2d", num), bg, colors.white, x, x2)
        end
    end

    -- Bold yellow arrows pointing at ball (in the middle of the wheel)
    drawArrows(WHEEL[((offset - 1 + BCELL) % WLEN + WLEN) % WLEN + 1])

    -- Black top/bottom rails
    mfill(1, WY1, MW, WY1, colors.black)
    mfill(1, WY2, MW, WY2, colors.black)

    -- Result: extra bright arrows
    if stopped and stoppedNum ~= nil then
        local bx = 1 + BCELL * CW
        -- Extra emphasis: extend arrows by 2 more rows
        if bx - AW - 1 >= 1 then
            for dy = -(AH//2+1), AH//2+1 do
                mwrite(bx - AW - 1, WMID + dy, string.rep(">", AW), colors.black, colors.yellow)
            end
        end
        if bx + CW + AW - 1 <= MW then
            for dy = -(AH//2+1), AH//2+1 do
                mwrite(bx + CW, WMID + dy, string.rep("<", AW), colors.black, colors.yellow)
            end
        end
    end
end

-- ── Compact bet grid ──────────────────────────────────────────────
local function betAmount(btype, bvalue)
    local sum = 0
    for _, b in ipairs(game.bets) do
        if b.btype == btype and b.bvalue == bvalue then sum = sum + b.amount end
    end
    return sum
end

local function betAmountType(btype)
    local sum = 0
    for _, b in ipairs(game.bets) do
        if b.btype == btype then sum = sum + b.amount end
    end
    return sum
end

local function showBet(x, y, amount)
    if amount <= 0 then return end
    mon.setCursorPos(x, y)
    mon.setBackgroundColor(colors.yellow)
    mon.setTextColor(colors.black)
    mon.write(tostring(amount))
end

local function numGridPos(n)
    if n == 0 then return nil end
    local col = math.ceil(n / 3)
    local row = 4 - (n % 3 == 0 and 3 or n % 3)
    return col, row
end

local function numCellX(col) return ZERO_W + 1 + (col - 1) * NUM_W end
local function numCellY(row) return GY + (row - 1) * NUM_H end

local function drawGrid()
    -- Background: 3×NUM_H number rows + 2 dozen + 2 outside = 10 rows
    local gridH = NUM_ROWS * NUM_H + 4
    mfill(1, GY, MW, GY + gridH - 1, colors.green)

    -- 0 cell (spans all number rows on the left)
    local zH = NUM_ROWS * NUM_H
    mfill(1, GY, ZERO_W, GY + zH - 1, colors.lime)
    mwriteC(GY + math.floor(zH / 2), "0", colors.lime, colors.white, 1, ZERO_W)
    local za = betAmount("number", 0)
    if za > 0 then showBet(2, GY + math.floor(zH / 2), za) end

    -- Number cells (NUM_H rows each: content row + green border row)
    for n = 1, 36 do
        local col, row = numGridPos(n)
        local x   = numCellX(col)
        local y   = numCellY(row)
        local bg  = numBg(n)
        local isR = (game.phase == "result" and game.result == n)
        local cbg = isR and colors.yellow or bg
        local cfg = isR and colors.black  or colors.white

        -- Content rows (all but last row of cell)
        mfill(x, y, x + NUM_W - 2, y + NUM_H - 2, cbg)
        -- Right border
        mfill(x + NUM_W - 1, y, x + NUM_W - 1, y + NUM_H - 2, colors.green)
        -- Bottom border row
        mfill(x, y + NUM_H - 1, x + NUM_W - 1, y + NUM_H - 1, colors.green)

        local lbl = string.format("%-" .. (NUM_W - 1) .. "s", tostring(n)):sub(1, NUM_W - 1)
        mwrite(x, y, lbl, cbg, cfg)
        local amt = betAmount("number", n)
        if amt > 0 then showBet(x + NUM_W - 2, y, amt) end
    end

    -- Column bets (right side, NUM_H rows each)
    local cbX = ZERO_W + NUM_COLS * NUM_W + 1
    local colBets = {{"col3","2:1"},{"col2","2:1"},{"col1","2:1"}}
    for i, cb in ipairs(colBets) do
        local y = numCellY(i)
        mfill(cbX, y, cbX + COL_BET_W - 1, y + NUM_H - 1, colors.yellow)
        mwriteC(y, cb[2], colors.yellow, colors.black, cbX, cbX + COL_BET_W - 1)
        local amt = betAmountType(cb[1])
        if amt > 0 then showBet(cbX, y, amt) end
    end

    -- Dozen row (2 rows, after number grid)
    local dozenY = GY + NUM_ROWS * NUM_H
    local dW = math.floor((MW - ZERO_W - COL_BET_W) / 3)
    local dozens = {
        {ZERO_W+1,        dW,                             "dozen1","1st 12",colors.cyan},
        {ZERO_W+dW+1,     dW,                             "dozen2","2nd 12",colors.cyan},
        {ZERO_W+dW*2+1,   MW - ZERO_W - COL_BET_W - dW*2,"dozen3","3rd 12",colors.cyan},
    }
    for _, d in ipairs(dozens) do
        mfill(d[1], dozenY, d[1]+d[2]-1, dozenY+1, d[5])
        mwriteC(dozenY, d[4], d[5], colors.white, d[1], d[1]+d[2]-1)
        local amt = betAmountType(d[3])
        if amt > 0 then showBet(d[1], dozenY, amt) end
    end
    mfill(cbX, dozenY, cbX + COL_BET_W - 1, dozenY + 1, colors.black)

    -- Outside bets (2 rows)
    local outsideY = dozenY + 2
    local oW = math.floor(MW / 6)
    local outside = {
        {1,       "low",   "1-18",  colors.blue},
        {oW+1,    "even",  "Even",  colors.blue},
        {oW*2+1,  "red",   "Red",   colors.red},
        {oW*3+1,  "black", "Black", colors.gray},
        {oW*4+1,  "odd",   "Odd",   colors.blue},
        {oW*5+1,  "high",  "19-36", colors.blue},
    }
    for _, o in ipairs(outside) do
        local x2 = math.min(o[1] + oW - 1, MW)
        mfill(o[1], outsideY, x2, outsideY+1, o[4])
        mwriteC(outsideY, o[3], o[4], colors.white, o[1], x2)
        local amt = betAmountType(o[2])
        if amt > 0 then showBet(o[1], outsideY, amt) end
    end

    -- Result highlight on 0
    if game.phase == "result" and game.result == 0 then
        mfill(1, GY, ZERO_W, GY + zH - 1, colors.yellow)
        mwriteC(GY + math.floor(zH / 2), "0", colors.yellow, colors.black, 1, ZERO_W)
    end
end

-- ── Player list (bottom 2 rows) ───────────────────────────────────
local function drawPlayers()
    local sepY = MH - 1
    mfill(1, sepY, MW, MH, colors.black)
    mfill(1, sepY, MW, sepY, colors.gray, "-")

    local perCol = math.max(1, math.floor(MW / 30))
    local colW   = math.floor(MW / perCol)
    local count  = 0

    for _, p in pairs(game.players) do
        local bTotal = 0
        for _, b in ipairs(game.bets) do
            if b.pid == p.id then bTotal = bTotal + b.amount end
        end
        local line = string.format("%-10s %5d", p.username:sub(1,10), p.balance)
        if bTotal > 0 then line = line .. " b:" .. bTotal end
        for _, po in ipairs(game.payouts) do
            if po.username == p.username then
                line = line .. (po.delta >= 0 and " +" or " ") .. po.delta
            end
        end
        local px = (count % perCol) * colW + 1
        local py = sepY + 1 + math.floor(count / perCol)
        if py <= MH then
            mwrite(px, py, line:sub(1, colW), colors.black,
                bTotal > 0 and colors.cyan or colors.lightGray)
        end
        count = count + 1
    end
end

-- ── Full monitor redraw ───────────────────────────────────────────
local function drawAll()
    mon.setBackgroundColor(colors.black)
    mon.clear()

    -- Title bar
    mfill(1, 1, MW, 1, colors.yellow)
    local phase_labels = {
        waiting  = "* ROULETTE * TOUCH TO START *",
        betting  = ">> PLACE YOUR BETS!  " .. game.betLeft .. "s <<",
        spinning = "*** NO MORE BETS  -  SPINNING! ***",
        result   = game.result ~= nil and ("RESULT: " .. game.result ..
            (game.result == 0 and "  GREEN!" or
             RED[game.result] and "  RED!"   or "  BLACK!")) or "RESULT",
    }
    mwriteC(1, phase_labels[game.phase] or game.phase:upper(), colors.yellow, colors.black)

    drawWheel(game.animOffset, game.phase == "result", game.result)
    drawGrid()
    drawPlayers()
end

-- ── Terminal ──────────────────────────────────────────────────────
local function drawTerminal()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.yellow)
    print("=== ROULETTE TABLE ===")
    term.setTextColor(colors.white)
    print("Phase: " .. game.phase .. "  Players: " .. (function()
        local c=0; for _ in pairs(game.players) do c=c+1 end; return c
    end)())
    print("Bets: " .. #game.bets)
    if game.result then
        term.setTextColor(colors.cyan)
        print("Last result: " .. game.result)
    end
    term.setTextColor(colors.gray)
    print(string.rep("-", 40))
    term.setTextColor(colors.white)
    if game.phase == "waiting" then
        print("[ENTER] Start betting round")
    elseif game.phase == "result" then
        print("[ENTER] New round")
    end
end

-- ── Phase transitions ─────────────────────────────────────────────
local function startBetting()
    game.phase   = "betting"
    game.bets    = {}
    game.payouts = {}
    game.betLeft = BET_SECONDS
    if game.betTimer then os.cancelTimer(game.betTimer) end
    game.betTimer = os.startTimer(1)
    broadcast({type="phase", phase="betting", betLeft=game.betLeft})
    drawAll(); drawTerminal()
end

local function startSpinning()
    game.phase = "spinning"
    if game.betTimer then os.cancelTimer(game.betTimer) end
    game.betTimer = nil
    game.result     = WHEEL[math.random(1, WLEN)]
    game.animFrames = buildAnim(game.result)
    game.animIdx    = 1
    game.animOffset = game.animFrames[1]
    if game.animTimer then os.cancelTimer(game.animTimer) end
    game.animTimer = os.startTimer(ANIM_DELAYS[1] or 0.04)
    broadcast({type="phase", phase="spinning"})
    drawAll(); drawTerminal()
end

local function finishRound()
    game.phase = "result"
    if game.animTimer then os.cancelTimer(game.animTimer) end
    game.animTimer = nil
    local rIdx = wheelIdx(game.result)
    game.animOffset = ((rIdx - BCELL - 1) % WLEN + WLEN) % WLEN + 1

    local totals = {}
    for _, b in ipairs(game.bets) do
        totals[b.username] = totals[b.username] or 0
        if betWins(b.btype, b.bvalue, game.result) then
            local mult = PAYOUTS[b.btype] or 1
            totals[b.username] = totals[b.username] + b.amount * mult
        else
            totals[b.username] = totals[b.username] - b.amount
        end
    end

    game.payouts = {}
    local casinoDelta = 0
    for username, delta in pairs(totals) do
        game.payouts[#game.payouts+1] = {username=username, delta=delta}
        updateChips(username, delta)
        casinoDelta = casinoDelta - delta   -- casino gains losses, pays winnings
        for _, p in pairs(game.players) do
            if p.username == username then
                p.balance = math.max(0, p.balance + delta)
            end
        end
    end
    -- Update casino house account (negative delta = casino paid out winnings)
    if casinoDelta ~= 0 then
        updateChips("CASINO", casinoDelta)
    end

    broadcast({type="result", result=game.result, payouts=game.payouts})
    if game.resTimer then os.cancelTimer(game.resTimer) end
    game.resTimer = os.startTimer(RESULT_SECONDS)
    drawAll(); drawTerminal()
end

local function resetToWaiting()
    game.phase  = "waiting"
    game.bets   = {}
    game.result = nil
    if game.resTimer then os.cancelTimer(game.resTimer) end
    game.resTimer = nil
    broadcast({type="phase", phase="waiting"})
    drawAll(); drawTerminal()
end

-- ── Network handler ───────────────────────────────────────────────
local function handleMsg(sid, raw)
    local ok2, msg = pcall(textutils.unserialize, raw)
    if not ok2 or type(msg) ~= "table" then return end

    if msg.type == "join" then
        local username = msg.username
        if not username then return end
        if game.players[sid] then
            sendTo(sid, {type="joined", username=username,
                balance=game.players[sid].balance,
                phase=game.phase, betLeft=game.betLeft})
            return
        end
        local bal = getBalance(username) or 0
        game.players[sid] = {id=sid, username=username, balance=bal}
        sendTo(sid, {type="joined", username=username, balance=bal,
            phase=game.phase, betLeft=game.betLeft})
        drawAll(); drawTerminal()

    elseif msg.type == "bet" then
        if game.phase ~= "betting" then
            sendTo(sid, {type="error", msg="Betting is closed."}); return
        end
        local p = game.players[sid]
        if not p then sendTo(sid, {type="error", msg="Not joined."}); return end

        local btype  = msg.btype
        local bvalue = msg.bvalue
        local amount = math.floor(tonumber(msg.amount) or 0)

        if amount < MIN_BET then
            sendTo(sid, {type="error", msg="Minimum bet is "..MIN_BET}); return
        end
        local currentBets = 0
        for _, b in ipairs(game.bets) do
            if b.pid == sid then currentBets = currentBets + b.amount end
        end
        if currentBets + amount > p.balance then
            sendTo(sid, {type="error", msg="Not enough chips!"}); return
        end

        game.bets[#game.bets+1] = {
            pid=sid, username=p.username,
            btype=btype, bvalue=bvalue, amount=amount
        }
        sendTo(sid, {type="betOk", btype=btype, bvalue=bvalue, amount=amount})
        drawAll()

    elseif msg.type == "clearBets" then
        local newBets = {}
        for _, b in ipairs(game.bets) do
            if b.pid ~= sid then newBets[#newBets+1] = b end
        end
        game.bets = newBets
        sendTo(sid, {type="betsCleared"})
        drawAll()

    elseif msg.type == "leave" then
        game.players[sid] = nil
        local newBets = {}
        for _, b in ipairs(game.bets) do
            if b.pid ~= sid then newBets[#newBets+1] = b end
        end
        game.bets = newBets
        drawAll(); drawTerminal()
    end
end

-- ── Main loop ─────────────────────────────────────────────────────
drawAll()
drawTerminal()

while true do
    local ev, a, b, c = os.pullEvent()

    if ev == "timer" then
        if a == game.betTimer and game.phase == "betting" then
            game.betLeft = game.betLeft - 1
            if game.betLeft <= 0 then
                startSpinning()
            else
                game.betTimer = os.startTimer(1)
                broadcast({type="betLeft", betLeft=game.betLeft})
                drawAll(); drawTerminal()
            end

        elseif a == game.animTimer and game.phase == "spinning" then
            game.animIdx = game.animIdx + 1
            if game.animIdx > #game.animFrames then
                finishRound()
            else
                game.animOffset = game.animFrames[game.animIdx]
                local delay = ANIM_DELAYS[game.animIdx] or 0.30
                game.animTimer = os.startTimer(delay)
                drawAll()
            end

        elseif a == game.resTimer and game.phase == "result" then
            resetToWaiting()
        end

    elseif ev == "rednet_message" then
        local sid, raw, proto = a, b, c
        if proto == PROTOCOL then handleMsg(sid, raw) end

    elseif ev == "monitor_touch" or (ev == "key" and a == keys.enter) then
        if game.phase == "waiting" then
            startBetting()
        elseif game.phase == "result" then
            resetToWaiting()
        end
    end
end
