-- roulette/player.lua
-- Roulette player app for pocket PC
-- Reads casino session from client.lua

local PROTOCOL     = "roulette"
local CASINO_PROTO = "casino"
local SESSION_FILE = "/casino_session"
local TIMEOUT      = 5

local W, H = term.getSize()

-- ── Modem ─────────────────────────────────────────────────────────
local function openModem()
    local m = peripheral.find("modem", function(_, p) return p.isWireless() end)
    if not m then error("No wireless modem!", 0) end
    rednet.open(peripheral.getName(m))
end

-- ── Session ───────────────────────────────────────────────────────
local username, startChips
if fs.exists(SESSION_FILE) then
    local f = fs.open(SESSION_FILE, "r")
    local s = textutils.unserialize(f.readAll())
    f.close(); fs.delete(SESSION_FILE)
    if type(s) == "table" and s.username then
        username   = s.username
        startChips = s.chips or 0
    end
end
if not username then
    term.clear(); term.setCursorPos(1,1)
    term.setTextColor(colors.red)
    print("No casino session found.")
    print("Launch from casino_app!")
    os.sleep(3); return
end

-- ── Find table ────────────────────────────────────────────────────
openModem()
local tableID = nil
local function findTable()
    rednet.broadcast(textutils.serialize({type="join", username=username}), PROTOCOL)
    local sid, raw = rednet.receive(PROTOCOL, 4)
    if not sid then return nil end
    local ok2, msg = pcall(textutils.unserialize, raw)
    if ok2 and type(msg)=="table" and msg.type=="joined" then
        tableID = sid
        return msg
    end
end

-- ── State ─────────────────────────────────────────────────────────
local st = {
    balance   = startChips,
    phase     = "connecting",
    betLeft   = 0,
    myBets    = {},    -- {btype, bvalue, amount}
    pendingBet = nil,  -- {btype, bvalue} waiting for amount
    chipAmt   = 10,    -- currently selected chip size
    msg       = "",
    result    = nil,
    payout    = nil,
}

local CHIP_SIZES = {1, 5, 10, 25, 50, 100, 500}
local CHIP_COLORS = {
    [1]=colors.white, [5]=colors.cyan, [10]=colors.blue,
    [25]=colors.green, [50]=colors.orange, [100]=colors.red,
    [500]=colors.purple,
}

local function sendTable(msg)
    if not tableID then return end
    rednet.send(tableID, textutils.serialize(msg), PROTOCOL)
end

-- ── Button system ─────────────────────────────────────────────────
local btns = {}
local function addBtn(id, x, y, w, h, text, bg, fg)
    btns[#btns+1] = {id=id, x=x, y=y, w=w, h=h or 1, text=text, bg=bg, fg=fg}
end
local function drawBtns()
    for _, b in ipairs(btns) do
        for dy = 0, b.h-1 do
            term.setCursorPos(b.x, b.y + dy)
            term.setBackgroundColor(b.bg)
            term.setTextColor(b.fg)
            term.write(string.rep(" ", b.w))
        end
        local tx = b.x + math.floor((b.w - math.min(#b.text, b.w)) / 2)
        local ty = b.y + math.floor(b.h / 2)
        term.setCursorPos(tx, ty)
        term.write(b.text:sub(1, b.w))
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end
local function clickBtn(mx, my)
    for _, b in ipairs(btns) do
        if mx >= b.x and mx < b.x + b.w and my >= b.y and my < b.y + b.h then
            return b.id
        end
    end
end
local function cls()
    term.setBackgroundColor(colors.black); term.clear(); term.setCursorPos(1,1)
end
local function header(title, bg)
    bg = bg or colors.green
    local fg = (bg == colors.yellow or bg == colors.white) and colors.black or colors.yellow
    term.setCursorPos(1,1)
    term.setBackgroundColor(bg); term.setTextColor(fg)
    term.write(string.format("%-"..W.."s",""))
    local tx = math.floor((W - #title)/2) + 1
    term.setCursorPos(tx,1); term.write(title)
    term.setBackgroundColor(colors.black); term.setTextColor(colors.white)
    term.setCursorPos(1,2); term.write(string.rep("-",W))
end
local function statusBar(text, clr)
    term.setCursorPos(1, H)
    term.setBackgroundColor(clr == colors.red and colors.red or colors.black)
    term.setTextColor(clr == colors.red and colors.white or (clr or colors.lightGray))
    term.clearLine()
    term.write((" "..text):sub(1,W))
    term.setBackgroundColor(colors.black)
end

-- ── Bet type labels ───────────────────────────────────────────────
local BET_LABELS = {
    red="Red", black="Black", even="Even", odd="Odd",
    low="1-18", high="19-36",
    dozen1="1st 12", dozen2="2nd 12", dozen3="3rd 12",
    col1="Col 1", col2="Col 2", col3="Col 3",
}
local function betLabel(btype, bvalue)
    if btype == "number" then return "#"..tostring(bvalue) end
    return BET_LABELS[btype] or btype
end

-- ── Main betting screen ───────────────────────────────────────────
local function drawMain()
    cls(); btns = {}
    local phaseClr = {
        betting=colors.green, spinning=colors.orange,
        result=colors.cyan, waiting=colors.gray, connecting=colors.gray
    }
    header("ROULETTE", phaseClr[st.phase] or colors.gray)

    -- Balance and phase
    term.setCursorPos(1,3); term.setTextColor(colors.yellow)
    term.write("  Chips: "..st.balance)
    term.setCursorPos(1,4); term.setTextColor(colors.lightGray)
    if st.phase == "betting" then
        term.write("  Betting open: "..st.betLeft.."s left")
    elseif st.phase == "spinning" then
        term.write("  Wheel spinning...")
    elseif st.phase == "result" and st.result ~= nil then
        local rBg = (st.result == 0) and "green" or
                    (({[true]="red",[false]="black"})[({[true]=true})[({[1]=true,[3]=true,[5]=true,[7]=true,[9]=true,[12]=true,[14]=true,[16]=true,[18]=true,[19]=true,[21]=true,[23]=true,[25]=true,[27]=true,[30]=true,[32]=true,[34]=true,[36]=true})[st.result]] or false])
        term.setTextColor(colors.cyan)
        term.write("  Result: "..st.result)
        if st.payout then
            term.setCursorPos(1,5)
            if st.payout >= 0 then
                term.setTextColor(colors.yellow); term.write("  Won: +"..st.payout.." chips!")
            else
                term.setTextColor(colors.red); term.write("  Lost: "..st.payout.." chips")
            end
        end
    elseif st.phase == "waiting" then
        term.write("  Waiting for next round...")
    end

    -- Chip selector (row 6)
    term.setCursorPos(1,6); term.setTextColor(colors.lightGray)
    term.write("Chip size:")
    local cx = 1
    for _, sz in ipairs(CHIP_SIZES) do
        if cx + #tostring(sz) + 2 <= W then
            local clr = CHIP_COLORS[sz] or colors.white
            local selected = (sz == st.chipAmt)
            addBtn("chip_"..sz, cx, 7, #tostring(sz)+2, 1,
                " "..sz.." ",
                selected and colors.yellow or clr,
                selected and colors.black or colors.black)
            cx = cx + #tostring(sz) + 2
        end
    end

    if st.phase == "betting" then
        -- Bet type buttons (rows 9-14)
        term.setCursorPos(1,9); term.setTextColor(colors.lightGray)
        term.write("Place bet:")

        local bw = math.floor((W-2) / 2)
        -- Outside bets
        local outsideBets = {
            {"red",   "RED",   colors.red,    colors.white},
            {"black", "BLACK", colors.gray,   colors.white},
            {"even",  "EVEN",  colors.blue,   colors.white},
            {"odd",   "ODD",   colors.blue,   colors.white},
            {"low",   "1-18",  colors.teal,   colors.white},
            {"high",  "19-36", colors.teal,   colors.white},
        }
        for i, ob in ipairs(outsideBets) do
            local col = (i-1) % 2
            local row = math.floor((i-1) / 2)
            addBtn("bet_"..ob[1], 1 + col*(bw+1), 10 + row, bw, 1,
                ob[2], ob[3], ob[4])
        end

        -- Dozens
        local dw = math.floor(W / 3)
        addBtn("bet_dozen1", 1,       14, dw,   1, "1st 12", colors.purple, colors.white)
        addBtn("bet_dozen2", dw+1,    14, dw,   1, "2nd 12", colors.purple, colors.white)
        addBtn("bet_dozen3", dw*2+1,  14, W-dw*2, 1, "3rd 12", colors.purple, colors.white)

        -- Number bet button
        addBtn("bet_number", 1, 16, W-2, 1, "BET ON NUMBER (0-36)", colors.orange, colors.black)

        -- My current bets
        if #st.myBets > 0 then
            term.setCursorPos(1,18); term.setTextColor(colors.lightGray)
            term.write("Your bets:")
            local total = 0
            for i, b in ipairs(st.myBets) do
                if 18+i <= H-3 then
                    term.setCursorPos(1, 18+i)
                    term.setTextColor(colors.white)
                    term.write("  "..betLabel(b.btype, b.bvalue).." = "..b.amount.." chips")
                    total = total + b.amount
                end
            end
            term.setCursorPos(1, H-3)
            term.setTextColor(colors.yellow)
            term.write("  Total bet: "..total)
        end

        addBtn("clear",  1,   H-2, math.floor((W-2)/2),   1, "CLEAR BETS",  colors.red,   colors.white)
        addBtn("leave",  math.floor(W/2)+1, H-2, math.floor(W/2)-1, 1, "LEAVE",  colors.gray,  colors.white)
    else
        addBtn("leave", 1, H-2, W-2, 1, "LEAVE TABLE", colors.red, colors.white)
    end

    drawBtns()
    if st.msg ~= "" then statusBar(st.msg, colors.lightGray) end
end

-- ── Number picker ─────────────────────────────────────────────────
local numberPickPage = 0
local function drawNumberPicker()
    cls(); btns = {}
    header("PICK NUMBER", colors.orange)
    term.setCursorPos(1,3); term.setTextColor(colors.yellow)
    term.write("  Chip: "..st.chipAmt.."  |  Balance: "..st.balance)

    -- Grid: 0-36, 7 per row
    local perRow = 7
    local bw = math.floor(W / perRow)
    for n = 0, 36 do
        local row = math.floor(n / perRow)
        local col = n % perRow
        local x   = col * bw + 1
        local y   = 4 + row
        if y <= H-3 then
            local bg = colors.gray
            if n == 0 then bg = colors.lime
            elseif ({[1]=1,[3]=1,[5]=1,[7]=1,[9]=1,[12]=1,[14]=1,[16]=1,[18]=1,
                     [19]=1,[21]=1,[23]=1,[25]=1,[27]=1,[30]=1,[32]=1,[34]=1,[36]=1})[n] then
                bg = colors.red
            end
            addBtn("num_"..n, x, y, bw, 1, string.format("%2d", n), bg, colors.white)
        end
    end

    addBtn("back", 1, H-1, W-2, 1, "BACK", colors.gray, colors.white)
    drawBtns()
end

-- ── Event loop ────────────────────────────────────────────────────
local function handleTableMsg(raw)
    local ok2, msg = pcall(textutils.unserialize, raw)
    if not ok2 or type(msg) ~= "table" then return end

    if msg.type == "joined" then
        st.balance = msg.balance or st.balance
        st.phase   = msg.phase  or "waiting"
        st.betLeft = msg.betLeft or 0
        st.msg     = "Connected!"

    elseif msg.type == "phase" then
        st.phase   = msg.phase
        st.betLeft = msg.betLeft or st.betLeft
        if msg.phase == "spinning" then
            st.myBets = {}
            st.payout = nil
            st.msg    = "No more bets!"
        elseif msg.phase == "waiting" then
            st.result = nil
            st.payout = nil
            st.msg    = "New round starting..."
        elseif msg.phase == "betting" then
            st.result = nil
            st.payout = nil
            st.msg    = "Place your bets!"
        end

    elseif msg.type == "betLeft" then
        st.betLeft = msg.betLeft

    elseif msg.type == "betOk" then
        st.myBets[#st.myBets+1] = {
            btype=msg.btype, bvalue=msg.bvalue, amount=msg.amount
        }
        st.balance = st.balance - msg.amount
        st.msg     = "Bet placed: "..betLabel(msg.btype, msg.bvalue)

    elseif msg.type == "betsCleared" then
        -- Recalculate balance
        local refund = 0
        for _, b in ipairs(st.myBets) do refund = refund + b.amount end
        st.balance = st.balance + refund
        st.myBets  = {}
        st.msg     = "Bets cleared."

    elseif msg.type == "result" then
        st.phase  = "result"
        st.result = msg.result
        if msg.payouts then
            for _, po in ipairs(msg.payouts) do
                if po.username == username then
                    st.payout  = po.delta
                    st.balance = st.balance + po.delta
                    break
                end
            end
        end
        st.myBets = {}

    elseif msg.type == "error" then
        st.msg = "Error: "..(msg.msg or "?")
    end
end

-- Connecting screen
cls()
header("ROULETTE", colors.gray)
term.setCursorPos(1,4); term.setTextColor(colors.lightGray)
term.write("  Connecting as "..username.."...")
term.setCursorPos(1,6); term.write("  Searching for table...")

local joinResp = findTable()
if not joinResp then
    term.setCursorPos(1,8); term.setTextColor(colors.red)
    term.write("  No roulette table found!")
    term.setCursorPos(1,10); term.setTextColor(colors.lightGray)
    term.write("  Make sure roulette_table is running.")
    os.sleep(4); return
end

st.balance = joinResp.balance or startChips
st.phase   = joinResp.phase   or "waiting"
st.betLeft = joinResp.betLeft or 0
st.msg     = "Connected to table!"

local inNumberPicker = false
drawMain()

while true do
    local ev, a, b, c = os.pullEvent()

    if ev == "rednet_message" then
        local sid, raw, proto = a, b, c
        if proto == PROTOCOL and sid == tableID then
            handleTableMsg(raw)
            if inNumberPicker then drawNumberPicker()
            else drawMain() end
        end

    elseif ev == "mouse_click" then
        local _, mx, my = ev, a, b  -- pullEvent gives (type, button, x, y) for mouse_click
        -- Correct unpacking: ev=mouse_click, a=button, b=x, c=y
        mx, my = b, c
        local bid = clickBtn(mx, my)
        if not bid then goto continue end

        if inNumberPicker then
            if bid == "back" then
                inNumberPicker = false
                drawMain()
            elseif bid:sub(1,4) == "num_" then
                local n = tonumber(bid:sub(5))
                sendTable({type="bet", btype="number", bvalue=n, amount=st.chipAmt})
                inNumberPicker = false
                drawMain()
            end
        else
            if bid:sub(1,5) == "chip_" then
                st.chipAmt = tonumber(bid:sub(6)) or st.chipAmt
                drawMain()
            elseif bid == "bet_number" then
                inNumberPicker = true
                drawNumberPicker()
            elseif bid:sub(1,4) == "bet_" then
                local btype = bid:sub(5)
                sendTable({type="bet", btype=btype, bvalue=nil, amount=st.chipAmt})
                drawMain()
            elseif bid == "clear" then
                sendTable({type="clearBets"})
                drawMain()
            elseif bid == "leave" then
                sendTable({type="leave"})
                cls(); return
            end
        end
    end

    ::continue::
end
