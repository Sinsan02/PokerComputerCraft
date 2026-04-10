-- casino/client.lua
-- Casino-app for lomme-PC / pocket computer
-- Krev: Tradlos modem

local PROTOCOL     = "casino"
local TIMEOUT      = 5
local SESSION_FILE = "/casino_session"

local W, H = term.getSize()
local session = {username=nil, chips=0, is_admin=false}

-- ── Modem ─────────────────────────────────────────────────────────
local function openModem()
    local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
    if not modem then error("Ingen tradlos modem!", 0) end
    rednet.open(peripheral.getName(modem))
end

local function casinoReq(msg)
    local sid = rednet.lookup(PROTOCOL)
    if not sid then return nil end
    rednet.send(sid, msg, PROTOCOL)
    local _, resp = rednet.receive(PROTOCOL, TIMEOUT)
    return resp
end

-- ── Button system ─────────────────────────────────────────────────
local btns = {}

local function addBtn(id, y, text, bg, fg)
    btns[#btns+1] = {id=id, x=3, y=y, w=W-4, text=text, bg=bg, fg=fg}
end

local function drawBtns()
    for _, b in ipairs(btns) do
        term.setCursorPos(b.x, b.y)
        term.setBackgroundColor(b.bg)
        term.setTextColor(b.fg)
        term.write(string.rep(" ", b.w))
        local tx = b.x + math.floor((b.w - #b.text) / 2)
        term.setCursorPos(tx, b.y)
        term.write(b.text)
    end
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function clickBtn(mx, my)
    for _, b in ipairs(btns) do
        if my == b.y and mx >= b.x and mx < b.x + b.w then
            return b.id
        end
    end
end

-- ── UI helpers ────────────────────────────────────────────────────
local function cls()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawHeader(title)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.green)
    term.setTextColor(colors.yellow)
    local line = string.format("%-" .. W .. "s", "")
    term.write(line)
    local tx = math.floor((W - #title) / 2) + 1
    term.setCursorPos(tx, 1)
    term.write(title)
    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, 2)
    term.setTextColor(colors.gray)
    term.write(string.rep("-", W))
    term.setTextColor(colors.white)
end

local function inputRow(y, label, masked)
    term.setCursorPos(1, y)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.lightGray)
    term.clearLine()
    term.write(label)
    term.setCursorPos(1, y + 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    local val = masked and read("*") or read()
    term.setBackgroundColor(colors.black)
    return val
end

local function showMsg(text, clr)
    term.setCursorPos(1, H)
    term.setBackgroundColor(clr == colors.red and colors.red or colors.black)
    term.setTextColor(clr == colors.red and colors.white or (clr or colors.lightGray))
    term.clearLine()
    term.write((" " .. text):sub(1, W))
    term.setBackgroundColor(colors.black)
end

-- ── Login screen ──────────────────────────────────────────────────
local function screenLogin()
    cls(); btns = {}
    drawHeader("LOGG INN")
    local username = inputRow(3, "Brukernavn:", false)
    local password = inputRow(6, "Passord:", true)
    addBtn("ok",   9,  "LOGG INN", colors.green, colors.black)
    addBtn("back", 11, "Tilbake",  colors.gray,  colors.white)
    drawBtns()

    while true do
        local ev, _, mx, my = os.pullEvent()
        if ev == "mouse_click" then
            local bid = clickBtn(mx, my)
            if bid == "ok" then
                showMsg("Kobler til...", colors.lightGray)
                local resp = casinoReq({type="login", username=username, password=password})
                if not resp then
                    showMsg("Finner ikke serveren!", colors.red)
                elseif not resp.ok then
                    showMsg(resp.msg or "Feil!", colors.red)
                else
                    session.username = username
                    session.chips    = resp.chips
                    session.is_admin = resp.is_admin
                    return true
                end
            elseif bid == "back" then
                return false
            end
        end
    end
end

-- ── Register screen ───────────────────────────────────────────────
local function screenRegister()
    cls(); btns = {}
    drawHeader("REGISTRER")
    local username = inputRow(3, "Brukernavn:", false)
    local password = inputRow(6, "Passord:", true)
    local confirm  = inputRow(9, "Bekreft passord:", true)
    addBtn("ok",   12, "OPPRETT BRUKER", colors.blue,  colors.white)
    addBtn("back", 14, "Tilbake",        colors.gray,  colors.white)
    drawBtns()

    while true do
        local ev, _, mx, my = os.pullEvent()
        if ev == "mouse_click" then
            local bid = clickBtn(mx, my)
            if bid == "ok" then
                if #username < 2 then
                    showMsg("Brukernavn for kort!", colors.red)
                elseif #password < 3 then
                    showMsg("Passord for kort (min 3)!", colors.red)
                elseif password ~= confirm then
                    showMsg("Passordene stemmer ikke!", colors.red)
                else
                    showMsg("Oppretter bruker...", colors.lightGray)
                    local resp = casinoReq({type="register", username=username, password=password})
                    if not resp then
                        showMsg("Serverfeil!", colors.red)
                    elseif not resp.ok then
                        showMsg(resp.msg or "Feil!", colors.red)
                    else
                        -- Auto-login etter registrering
                        local resp2 = casinoReq({type="login", username=username, password=password})
                        if resp2 and resp2.ok then
                            session.username = username
                            session.chips    = resp2.chips
                            session.is_admin = resp2.is_admin
                        end
                        return true
                    end
                end
            elseif bid == "back" then
                return false
            end
        end
    end
end

-- ── Auth menu ─────────────────────────────────────────────────────
local function screenAuth()
    while true do
        cls(); btns = {}
        drawHeader("CASINO")
        addBtn("login",    5, "LOGG INN",       colors.green,   colors.black)
        addBtn("register", 8, "REGISTRER",      colors.blue,    colors.white)
        addBtn("quit",    11, "AVSLUTT",        colors.gray,    colors.lightGray)
        drawBtns()

        local ev, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "login" then
            if screenLogin() then return end
        elseif bid == "register" then
            if screenRegister() then return end
        elseif bid == "quit" then
            cls(); os.shutdown()
        end
    end
end

-- ── Game menu ─────────────────────────────────────────────────────
local function refreshBalance()
    local resp = casinoReq({type="get_balance", username=session.username})
    if resp and resp.ok then session.chips = resp.chips end
end

local function screenGames()
    while true do
        refreshBalance()
        cls(); btns = {}
        drawHeader("VELG SPILL")

        term.setCursorPos(1, 3)
        term.setTextColor(colors.yellow)
        term.write("  Chips: " .. session.chips .. " kr")

        addBtn("poker",     5, "Texas Hold'em Poker",  colors.green,  colors.black)
        addBtn("blackjack", 8, "Blackjack  (snart)",   colors.gray,   colors.lightGray)
        addBtn("rulett",   11, "Rulett     (snart)",   colors.gray,   colors.lightGray)
        addBtn("back",     14, "Tilbake",              colors.red,    colors.white)
        drawBtns()

        local ev, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "poker" then
            if session.chips <= 0 then
                showMsg("Ikke nok chips! Ga til kassen.", colors.red)
                os.sleep(2)
            else
                -- Skriv session-fil slik at poker vet hvem du er
                local f = fs.open(SESSION_FILE, "w")
                f.write(textutils.serialize({
                    username = session.username,
                    chips    = session.chips,
                }))
                f.close()
                shell.run("poker/player")
                refreshBalance()
            end
        elseif bid == "back" then
            return
        end
    end
end

-- ── Hoved-meny ────────────────────────────────────────────────────
local function screenMain()
    while true do
        refreshBalance()
        cls(); btns = {}
        drawHeader("CASINO")

        term.setCursorPos(1, 4)
        term.setTextColor(colors.white)
        term.write("  " .. session.username)
        if session.is_admin then
            term.setTextColor(colors.cyan)
            term.write("  [ADMIN]")
        end

        term.setCursorPos(1, 5)
        term.setTextColor(colors.yellow)
        term.write("  Chips: " .. session.chips .. " kr")

        addBtn("games",  7,  "SPILL",    colors.green, colors.black)
        addBtn("logout", 10, "LOGG UT",  colors.red,   colors.white)
        drawBtns()

        local ev, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "games" then
            screenGames()
        elseif bid == "logout" then
            session = {username=nil, chips=0, is_admin=false}
            return
        end
    end
end

-- ── Main ──────────────────────────────────────────────────────────
openModem()
while true do
    screenAuth()
    if session.username then
        screenMain()
    end
end
