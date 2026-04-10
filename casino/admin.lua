-- casino/admin.lua
-- Casino Cashier Terminal (Admin)
-- Req: Wireless modem
-- Start: casino_admin

local PROTOCOL = "casino"
local TIMEOUT  = 5

local W, H = term.getSize()
local adminUser = nil
local adminPass = nil

-- ── Modem ─────────────────────────────────────────────────────────
local function openModem()
    local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
    if not modem then error("No wireless modem found!", 0) end
    rednet.open(peripheral.getName(modem))
end

local function request(msg)
    local sid = rednet.lookup(PROTOCOL)
    if not sid then return nil end
    rednet.send(sid, msg, PROTOCOL)
    local _, resp = rednet.receive(PROTOCOL, TIMEOUT)
    return resp
end

-- ── Buttons ───────────────────────────────────────────────────────
local btns = {}

local function rawAddBtn(id, x, y, w, text, bg, fg)
    btns[#btns+1] = {id=id, x=x, y=y, w=w, text=text, bg=bg, fg=fg, center=false}
end

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

local function drawHeader(title)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.yellow)
    term.setTextColor(colors.black)
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

-- ── Fetch user list ───────────────────────────────────────────────
local function fetchUsers()
    local resp = request({
        type           = "list_users",
        admin          = adminUser,
        admin_password = adminPass,
    })
    if not resp or not resp.ok then
        return nil, (resp and resp.msg or "server error")
    end
    return resp.users
end

-- ── User picker ───────────────────────────────────────────────────
local function pickUser()
    local users, err = fetchUsers()
    if not users then
        cls(); btns = {}
        drawHeader("SELECT USER")
        term.setCursorPos(1, 4); term.setTextColor(colors.red)
        term.write("  Error: " .. err)
        addBtn("back", H, "Back", colors.gray, colors.white)
        drawBtns(); os.pullEvent("mouse_click")
        return nil
    end
    if #users == 0 then
        cls(); btns = {}
        drawHeader("SELECT USER")
        term.setCursorPos(1, 4); term.setTextColor(colors.gray)
        term.write("  No users registered.")
        addBtn("back", H, "Back", colors.gray, colors.white)
        drawBtns(); os.pullEvent("mouse_click")
        return nil
    end

    local PAGE  = H - 4
    local page  = 1
    local pages = math.max(1, math.ceil(#users / PAGE))

    while true do
        cls(); btns = {}
        drawHeader("SELECT USER")

        local start = (page - 1) * PAGE + 1
        local y = 3
        for i = start, math.min(start + PAGE - 1, #users) do
            local u     = users[i]
            local right = u.chips .. " chips" .. (u.is_admin and " [A]" or "")
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
                rawAddBtn("prev", 1,      H-1, hw,     "< Prev", colors.lightGray, colors.black)
            end
            if page < pages then
                rawAddBtn("next", hw + 2, H-1, W-hw-2, "Next >", colors.lightGray, colors.black)
            end
        end
        addBtn("back", H, "Cancel", colors.red, colors.white)
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

-- ── View all users ────────────────────────────────────────────────
local function screenListUsers()
    local users, err = fetchUsers()
    local PAGE  = H - 6
    local page  = 1
    local pages = users and math.max(1, math.ceil(#users / PAGE)) or 1

    while true do
        cls(); btns = {}
        drawHeader("ALL USERS")

        if not users then
            term.setCursorPos(1, 4); term.setTextColor(colors.red)
            term.write("  Error: " .. err)
        elseif #users == 0 then
            term.setCursorPos(1, 4); term.setTextColor(colors.gray)
            term.write("  No users.")
        else
            term.setCursorPos(1, 3); term.setTextColor(colors.lightGray)
            term.write(string.format(" %-13s %6s", "Name", "Chips"))
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
                term.write(string.format(" %-13s %5d %s", u.username:sub(1, 13), u.chips, flag):sub(1, W))
                y = y + 1
            end

            if pages > 1 then
                term.setCursorPos(1, H-2); term.setTextColor(colors.gray)
                term.write(string.rep("-", W))
                local hw = math.floor(W / 2) - 1
                if page > 1 then
                    rawAddBtn("prev", 1, H-1, hw, "< Prev", colors.lightGray, colors.black)
                end
                if page < pages then
                    rawAddBtn("next", hw+2, H-1, W-hw-2, "Next >", colors.lightGray, colors.black)
                end
            end
        end

        addBtn("back", H, "Back", colors.gray, colors.white)
        drawBtns()

        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if     bid == "back" then return
        elseif bid == "prev" then page = page - 1
        elseif bid == "next" then page = page + 1
        end
    end
end

-- ── Add chips ─────────────────────────────────────────────────────
local function screenAddChips()
    local user = pickUser()
    if not user then return end

    cls(); btns = {}
    drawHeader("ADD CHIPS")

    term.setCursorPos(1, 3); term.setTextColor(colors.lightGray)
    term.write("  User:    "); term.setTextColor(colors.white); term.write(user.username)
    term.setCursorPos(1, 4); term.setTextColor(colors.lightGray)
    term.write("  Balance: "); term.setTextColor(colors.yellow); term.write(user.chips .. " chips")

    local rawAmt = inputRow(6, "Add amount:", false)
    local amount = tonumber(rawAmt)
    if not amount or amount <= 0 then
        showMsg("Invalid amount!", colors.red); os.sleep(1.5); return
    end

    term.setCursorPos(1, 9); term.setTextColor(colors.white)
    term.write("  + " .. amount .. " chips  →  " .. (user.chips + amount) .. " chips total")

    addBtn("ok",   11, "CONFIRM", colors.green, colors.black)
    addBtn("back", 13, "Cancel",  colors.red,   colors.white)
    drawBtns()

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "ok" then
            showMsg("Sending...", colors.lightGray)
            local resp = request({
                type="add_chips", admin=adminUser, admin_password=adminPass,
                target=user.username, amount=amount,
            })
            if not resp                 then showMsg("Server error!", colors.red)
            elseif not resp.ok          then showMsg(resp.msg or "Error!", colors.red)
            else showMsg(user.username .. " now has " .. resp.chips .. " chips", colors.green) end
            os.sleep(1.5); return
        elseif bid == "back" then return end
    end
end

-- ── Set chips ─────────────────────────────────────────────────────
local function screenSetChips()
    local user = pickUser()
    if not user then return end

    cls(); btns = {}
    drawHeader("SET CHIPS")

    term.setCursorPos(1, 3); term.setTextColor(colors.lightGray)
    term.write("  User:    "); term.setTextColor(colors.white); term.write(user.username)
    term.setCursorPos(1, 4); term.setTextColor(colors.lightGray)
    term.write("  Balance: "); term.setTextColor(colors.yellow); term.write(user.chips .. " chips")

    local rawAmt = inputRow(6, "Set chips to:", false)
    local amount = tonumber(rawAmt)
    if not amount or amount < 0 then
        showMsg("Invalid amount!", colors.red); os.sleep(1.5); return
    end

    term.setCursorPos(1, 9); term.setTextColor(colors.white)
    term.write("  " .. user.chips .. "  →  " .. amount .. " chips")

    addBtn("ok",   11, "CONFIRM", colors.green, colors.black)
    addBtn("back", 13, "Cancel",  colors.red,   colors.white)
    drawBtns()

    while true do
        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if bid == "ok" then
            showMsg("Sending...", colors.lightGray)
            local resp = request({
                type="set_chips", admin=adminUser, admin_password=adminPass,
                target=user.username, amount=amount,
            })
            if not resp                 then showMsg("Server error!", colors.red)
            elseif not resp.ok          then showMsg(resp.msg or "Error!", colors.red)
            else showMsg(user.username .. " now has " .. resp.chips .. " chips", colors.green) end
            os.sleep(1.5); return
        elseif bid == "back" then return end
    end
end

-- ── Login ─────────────────────────────────────────────────────────
local function screenLogin()
    while true do
        cls(); btns = {}
        drawHeader("CASINO ADMIN")
        local u = inputRow(3, "Username:", false)
        local p = inputRow(6, "Password:", true)
        addBtn("ok",   9,  "LOG IN", colors.yellow, colors.black)
        addBtn("quit", 11, "Quit",   colors.gray,   colors.white)
        drawBtns()

        while true do
            local _, _, mx, my = os.pullEvent("mouse_click")
            local bid = clickBtn(mx, my)
            if bid == "ok" then
                showMsg("Checking...", colors.lightGray)
                local resp = request({type="login", username=u, password=p})
                if not resp              then showMsg("Server not found!", colors.red)
                elseif not resp.ok       then showMsg(resp.msg or "Wrong password!", colors.red)
                elseif not resp.is_admin then showMsg("No admin access!", colors.red)
                else adminUser = u; adminPass = p; return end
                break
            elseif bid == "quit" then
                cls(); os.shutdown()
            end
        end
    end
end

-- ── Main menu ─────────────────────────────────────────────────────
local function screenMain()
    while true do
        cls(); btns = {}
        drawHeader("CASINO ADMIN")

        term.setCursorPos(1, 3)
        term.setTextColor(colors.lightGray)
        term.write("  " .. adminUser .. " [ADMIN]")

        addBtn("list",   5, "All users",   colors.blue,   colors.white)
        addBtn("add",    7, "Add chips",   colors.green,  colors.black)
        addBtn("set",    9, "Set chips",   colors.yellow, colors.black)
        addBtn("logout",12, "Log out",     colors.red,    colors.white)
        drawBtns()

        local _, _, mx, my = os.pullEvent("mouse_click")
        local bid = clickBtn(mx, my)
        if     bid == "list"   then screenListUsers()
        elseif bid == "add"    then screenAddChips()
        elseif bid == "set"    then screenSetChips()
        elseif bid == "logout" then adminUser = nil; adminPass = nil; return
        end
    end
end

-- ── Main ──────────────────────────────────────────────────────────
openModem()
while true do
    screenLogin()
    screenMain()
end
