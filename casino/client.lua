-- casino/client.lua
-- Casino-app for lomme-PC / pocket computer
-- Krev: Tradlos modem

local PROTOCOL     = "casino"
local TIMEOUT      = 5
local SESSION_FILE = "/casino_session"

local W, H = term.getSize()
local session = {username=nil, password=nil, chips=0, is_admin=false}

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

-- ── Buttons ───────────────────────────────────────────────────────
local btns = {}

-- Knapp med eksplisitt posisjon, venstrejustert tekst
local function rawAddBtn(id, x, y, w, text, bg, fg)
    btns[#btns+1] = {id=id, x=x, y=y, w=w, text=text, bg=bg, fg=fg, center=false}
end

-- Full-bredde sentrert knapp
local function addBtn(id, y, text, bg, fg)
    btns[#btns+1] = {id=id, x=3, y=y, w=W-4, text=text, bg=bg, fg=fg, center=true}
end

local function drawBtns()
    for _, b in ipairs(btns) do
        term.setCursorPos(b.x, b.y)
        term.setBackgroundColor(b.bg)
        term.setTextColor(b.fg)
        term.write(string.rep(" ", b.w))
        if b.center then
            local tx = b.x + math.floor((b.w - math.min(#b.text, b.w)) / 2)
            term.setCursorPos(tx, b.y)
        else
            term.setCursorPos(b.x, b.y)
        end
        term.write(b.text:sub(1, b.w))
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

local function drawHeader(title, bgClr)
    bgClr = bgClr or colors.green
    local fgClr = (bgClr == colors.yellow) and colors.black or colors.yellow
    term.setCursorPos(1, 1)
    term.setBackgroundColor(bgClr)
    term.setTextColor(fgClr)
    term.write(string.format("%-" .. W .. "s", ""))
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
    if clr == colors.red then
        term.setBackgroundColor(colors.red); term.setTextColor(colors.white)
    elseif clr == colors.green then
        term.setBackgroundColor(colors.black); term.setTextColor(colors.green)
    else
        term.setBackgroundColor(colors.black); term.setTextColor(clr or colors.lightGray)
    end
    term.clearLine()
    term.write((" " .. text):sub(1, W))
    term.setBackgroundColor(colors.black)
end

-- ── Login ─────────────────────────────────────────────────────────
local function screenLogin()
    cls(); btns = {}
    drawHeader("LOGG INN")
    local username = inputRow(3, "Brukernavn:", false)
    local password = inputRow(6, "Passord:", true)
    addBtn("ok",   9,  "LOGG INN", colors.green, colors.black)
    addBtn("back", 11, "Tilbake",  colors.gray,  colors.white)
    drawBtns()

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "ok" then
            showMsg("Kobler til...", colors.lightGray)
            local resp = casinoReq({type="login", username=username, password=password})
            if not resp              then showMsg("Finner ikke serveren!", colors.red)
            elseif not resp.ok       then showMsg(resp.msg or "Feil!", colors.red)
            else
                session.username = username
                session.password = password
                session.chips    = resp.chips
                session.is_admin = resp.is_admin
                return true
            end
        elseif bid == "back" then return false end
    end
end

-- ── Registrer ─────────────────────────────────────────────────────
local function screenRegister()
    cls(); btns = {}
    drawHeader("REGISTRER")
    local username = inputRow(3, "Brukernavn:", false)
    local password = inputRow(6, "Passord:", true)
    local confirm  = inputRow(9, "Bekreft passord:", true)
    addBtn("ok",   12, "OPPRETT BRUKER", colors.blue, colors.white)
    addBtn("back", 14, "Tilbake",        colors.gray, colors.white)
    drawBtns()

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "ok" then
            if #username < 2       then showMsg("Brukernavn for kort!", colors.red)
            elseif #password < 3   then showMsg("Passord for kort (min 3)!", colors.red)
            elseif password ~= confirm then showMsg("Passordene stemmer ikke!", colors.red)
            else
                showMsg("Oppretter bruker...", colors.lightGray)
                local resp = casinoReq({type="register", username=username, password=password})
                if not resp        then showMsg("Serverfeil!", colors.red)
                elseif not resp.ok then showMsg(resp.msg or "Feil!", colors.red)
                else
                    local resp2 = casinoReq({type="login", username=username, password=password})
                    if resp2 and resp2.ok then
                        session.username = username
                        session.password = password
                        session.chips    = resp2.chips
                        session.is_admin = resp2.is_admin
                    end
                    return true
                end
            end
        elseif bid == "back" then return false end
    end
end

-- ── Auth-meny ─────────────────────────────────────────────────────
local function screenAuth()
    while true do
        cls(); btns = {}
        drawHeader("CASINO")
        addBtn("login",    5, "LOGG INN",  colors.green, colors.black)
        addBtn("register", 8, "REGISTRER", colors.blue,  colors.white)
        addBtn("quit",    11, "AVSLUTT",   colors.gray,  colors.lightGray)
        drawBtns()

        local _, _, mx, my = os.pullEvent("mouse_click")
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

-- ── Admin: hent brukere ───────────────────────────────────────────
local function adminFetchUsers()
    local resp = casinoReq({
        type           = "list_users",
        admin          = session.username,
        admin_password = session.password,
    })
    if not resp or not resp.ok then
        return nil, (resp and resp.msg or "serverfeil")
    end
    return resp.users
end

-- ── Admin: brukerpicker ───────────────────────────────────────────
local function adminPickUser()
    local users, err = adminFetchUsers()
    if not users then
        cls(); btns = {}
        drawHeader("VELG BRUKER", colors.yellow)
        term.setCursorPos(1, 4); term.setTextColor(colors.red)
        term.write("  Feil: " .. err)
        addBtn("back", H, "Tilbake", colors.gray, colors.white)
        drawBtns(); os.pullEvent("mouse_click")
        return nil
    end
    if #users == 0 then
        cls(); btns = {}
        drawHeader("VELG BRUKER", colors.yellow)
        term.setCursorPos(1, 4); term.setTextColor(colors.gray)
        term.write("  Ingen brukere.")
        addBtn("back", H, "Tilbake", colors.gray, colors.white)
        drawBtns(); os.pullEvent("mouse_click")
        return nil
    end

    local PAGE  = H - 4
    local page  = 1
    local pages = math.max(1, math.ceil(#users / PAGE))

    while true do
        cls(); btns = {}
        drawHeader("VELG BRUKER", colors.yellow)

        local start = (page - 1) * PAGE + 1
        local y = 3
        for i = start, math.min(start + PAGE - 1, #users) do
            local u     = users[i]
            local right = u.chips .. " kr" .. (u.is_admin and " [A]" or "")
            local maxL  = W - #right - 2
            local left  = " " .. u.username:sub(1, maxL)
            local pad   = W - #left - #right
            local label = left .. string.rep(" ", math.max(0, pad)) .. right
            local fg    = u.is_admin and colors.cyan or colors.white
            rawAddBtn(i, 1, y, W, label, colors.gray, fg)
            y = y + 1
        end

        if pages > 1 then
            local hw = math.floor(W / 2) - 1
            if page > 1 then
                rawAddBtn("prev", 1, H-1, hw, "< Forrige", colors.lightGray, colors.black)
            end
            if page < pages then
                rawAddBtn("next", hw+2, H-1, W-hw-2, "Neste >", colors.lightGray, colors.black)
            end
        end
        addBtn("back", H, "Avbryt", colors.red, colors.white)
        drawBtns()

        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if type(bid) == "number" then return users[bid]
        elseif bid == "prev"     then page = page - 1
        elseif bid == "next"     then page = page + 1
        elseif bid == "back"     then return nil
        end
    end
end

-- ── Admin: se alle brukere ────────────────────────────────────────
local function adminScreenList()
    local users, err = adminFetchUsers()
    local PAGE  = H - 6
    local page  = 1
    local pages = users and math.max(1, math.ceil(#users / PAGE)) or 1

    while true do
        cls(); btns = {}
        drawHeader("ALLE BRUKERE", colors.yellow)

        if not users then
            term.setCursorPos(1, 4); term.setTextColor(colors.red)
            term.write("  Feil: " .. err)
        elseif #users == 0 then
            term.setCursorPos(1, 4); term.setTextColor(colors.gray)
            term.write("  Ingen brukere.")
        else
            term.setCursorPos(1, 3); term.setTextColor(colors.lightGray)
            term.write(string.format(" %-13s %6s", "Navn", "Chips"))
            term.setCursorPos(1, 4); term.setTextColor(colors.gray)
            term.write(string.rep("-", W))
            local start = (page - 1) * PAGE + 1
            local y = 5
            for i = start, math.min(start + PAGE - 1, #users) do
                local u = users[i]
                term.setCursorPos(1, y)
                if u.is_admin then term.setTextColor(colors.cyan)
                else               term.setTextColor(colors.white) end
                local flag = u.is_admin and "[A]" or "   "
                term.write(string.format(" %-13s %5d %s", u.username:sub(1,13), u.chips, flag):sub(1,W))
                y = y + 1
            end
            if pages > 1 then
                term.setCursorPos(1, H-2); term.setTextColor(colors.gray)
                term.write(string.rep("-", W))
                local hw = math.floor(W/2) - 1
                if page > 1 then rawAddBtn("prev",1,H-1,hw,"< Forrige",colors.lightGray,colors.black) end
                if page < pages then rawAddBtn("next",hw+2,H-1,W-hw-2,"Neste >",colors.lightGray,colors.black) end
            end
        end

        addBtn("back", H, "Tilbake", colors.gray, colors.white)
        drawBtns()

        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if     bid == "back" then return
        elseif bid == "prev" then page = page - 1
        elseif bid == "next" then page = page + 1
        end
    end
end

-- ── Admin: legg til chips ─────────────────────────────────────────
local function adminScreenAddChips()
    local user = adminPickUser()
    if not user then return end

    cls(); btns = {}
    drawHeader("LEGG TIL CHIPS", colors.yellow)
    term.setCursorPos(1,3); term.setTextColor(colors.lightGray)
    term.write("  Bruker: "); term.setTextColor(colors.white); term.write(user.username)
    term.setCursorPos(1,4); term.setTextColor(colors.lightGray)
    term.write("  Saldo:  "); term.setTextColor(colors.yellow); term.write(user.chips .. " kr")

    local rawAmt = inputRow(6, "Legg til (kr):", false)
    local amount = tonumber(rawAmt)
    if not amount or amount <= 0 then showMsg("Ugyldig belop!", colors.red); os.sleep(1.5); return end

    term.setCursorPos(1,9); term.setTextColor(colors.white)
    term.write("  + " .. amount .. " kr  →  " .. (user.chips + amount) .. " kr totalt")
    addBtn("ok",   11, "BEKREFT", colors.green, colors.black)
    addBtn("back", 13, "Avbryt",  colors.red,   colors.white)
    drawBtns()

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "ok" then
            local resp = casinoReq({
                type="add_chips", admin=session.username, admin_password=session.password,
                target=user.username, amount=amount,
            })
            if not resp        then showMsg("Serverfeil!", colors.red)
            elseif not resp.ok then showMsg(resp.msg or "Feil!", colors.red)
            else showMsg(user.username .. " har na " .. resp.chips .. " kr", colors.green) end
            os.sleep(1.5); return
        elseif bid == "back" then return end
    end
end

-- ── Admin: sett chips ─────────────────────────────────────────────
local function adminScreenSetChips()
    local user = adminPickUser()
    if not user then return end

    cls(); btns = {}
    drawHeader("SETT CHIPS", colors.yellow)
    term.setCursorPos(1,3); term.setTextColor(colors.lightGray)
    term.write("  Bruker: "); term.setTextColor(colors.white); term.write(user.username)
    term.setCursorPos(1,4); term.setTextColor(colors.lightGray)
    term.write("  Saldo:  "); term.setTextColor(colors.yellow); term.write(user.chips .. " kr")

    local rawAmt = inputRow(6, "Sett chips til (kr):", false)
    local amount = tonumber(rawAmt)
    if not amount or amount < 0 then showMsg("Ugyldig belop!", colors.red); os.sleep(1.5); return end

    term.setCursorPos(1,9); term.setTextColor(colors.white)
    term.write("  " .. user.chips .. " kr  →  " .. amount .. " kr")
    addBtn("ok",   11, "BEKREFT", colors.green, colors.black)
    addBtn("back", 13, "Avbryt",  colors.red,   colors.white)
    drawBtns()

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "ok" then
            local resp = casinoReq({
                type="set_chips", admin=session.username, admin_password=session.password,
                target=user.username, amount=amount,
            })
            if not resp        then showMsg("Serverfeil!", colors.red)
            elseif not resp.ok then showMsg(resp.msg or "Feil!", colors.red)
            else showMsg(user.username .. " har na " .. resp.chips .. " kr", colors.green) end
            os.sleep(1.5); return
        elseif bid == "back" then return end
    end
end

-- ── Admin-panel (for admin-brukere fra hoved-meny) ────────────────
local function screenAdminPanel()
    while true do
        cls(); btns = {}
        drawHeader("ADMIN PANEL", colors.yellow)
        term.setCursorPos(1, 3); term.setTextColor(colors.lightGray)
        term.write("  " .. session.username .. " [ADMIN]")
        addBtn("list",  5, "Alle brukere",   colors.blue,   colors.white)
        addBtn("add",   7, "Legg til chips", colors.green,  colors.black)
        addBtn("set",   9, "Sett chips",     colors.yellow, colors.black)
        addBtn("back", 12, "Tilbake",        colors.gray,   colors.white)
        drawBtns()

        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if     bid == "list" then adminScreenList()
        elseif bid == "add"  then adminScreenAddChips()
        elseif bid == "set"  then adminScreenSetChips()
        elseif bid == "back" then return
        end
    end
end

-- ── Spill-meny ────────────────────────────────────────────────────
local function refreshBalance()
    local resp = casinoReq({type="get_balance", username=session.username})
    if resp and resp.ok then session.chips = resp.chips end
end

local function screenGames()
    while true do
        refreshBalance()
        cls(); btns = {}
        drawHeader("VELG SPILL")
        term.setCursorPos(1, 3); term.setTextColor(colors.yellow)
        term.write("  Chips: " .. session.chips .. " kr")
        addBtn("poker",     5, "Texas Hold'em Poker", colors.green, colors.black)
        addBtn("blackjack", 8, "Blackjack  (snart)",  colors.gray,  colors.lightGray)
        addBtn("rulett",   11, "Rulett     (snart)",  colors.gray,  colors.lightGray)
        addBtn("back",     14, "Tilbake",             colors.red,   colors.white)
        drawBtns()

        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "poker" then
            if session.chips <= 0 then
                showMsg("Ikke nok chips! Ga til kassen.", colors.red)
                os.sleep(2)
            else
                local f = fs.open(SESSION_FILE, "w")
                f.write(textutils.serialize({username=session.username, chips=session.chips}))
                f.close()
                shell.run("poker/player")
                refreshBalance()
            end
        elseif bid == "back" then return end
    end
end

-- ── Hoved-meny ────────────────────────────────────────────────────
local function screenMain()
    while true do
        refreshBalance()
        cls(); btns = {}
        drawHeader("CASINO")

        term.setCursorPos(1, 4); term.setTextColor(colors.white)
        term.write("  " .. session.username)
        if session.is_admin then
            term.setTextColor(colors.cyan); term.write("  [ADMIN]")
        end
        term.setCursorPos(1, 5); term.setTextColor(colors.yellow)
        term.write("  Chips: " .. session.chips .. " kr")

        local btnY = 7
        addBtn("games", btnY, "SPILL", colors.green, colors.black)
        if session.is_admin then
            addBtn("admin", btnY + 3, "ADMIN PANEL", colors.yellow, colors.black)
            addBtn("logout", btnY + 6, "LOGG UT", colors.red, colors.white)
        else
            addBtn("logout", btnY + 3, "LOGG UT", colors.red, colors.white)
        end
        drawBtns()

        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "games" then
            screenGames()
        elseif bid == "admin" then
            screenAdminPanel()
        elseif bid == "logout" then
            session = {username=nil, password=nil, chips=0, is_admin=false}
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
