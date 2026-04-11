-- casino/db.lua
-- Casino Database Server
-- Req: Wireless modem attached to this computer
-- Start: casino_db  (shortcut created by install.lua)

local PROTOCOL  = "casino"
local DATA_FILE = "/casino_data/users"
local VERSION   = "1.0"

-- ── Utilities ──────────────────────────────────────────────────────
local function hash(s)
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % 2147483648
    end
    return tostring(h)
end

local function loadDB()
    if not fs.exists(DATA_FILE) then return {users = {}} end
    local f = fs.open(DATA_FILE, "r")
    local d = textutils.unserialize(f.readAll())
    f.close()
    return d or {users = {}}
end

local function saveDB(db)
    if not fs.exists("/casino_data") then fs.makeDir("/casino_data") end
    local f = fs.open(DATA_FILE, "w")
    f.write(textutils.serialize(db))
    f.close()
end

local function adminOK(db, admin, pass)
    local u = db.users[admin]
    return u and u.is_admin and u.password == hash(pass)
end

-- ── Request handlers ───────────────────────────────────────────────
local function handle(req, db)
    local t = req.type

    if t == "register" then
        if db.users[req.username] then
            return {ok=false, msg="Username is already taken"}
        end
        -- First user to register automatically becomes admin
        local is_admin = next(db.users) == nil
        db.users[req.username] = {
            password = hash(req.password),
            chips    = 0,
            is_admin = is_admin,
        }
        saveDB(db)
        return {ok=true, is_admin=is_admin}

    elseif t == "login" then
        local u = db.users[req.username]
        if not u then return {ok=false, msg="User not found"} end
        if u.password ~= hash(req.password) then return {ok=false, msg="Wrong password"} end
        return {ok=true, chips=u.chips, is_admin=u.is_admin}

    elseif t == "get_balance" then
        local u = db.users[req.username]
        if not u then return {ok=false} end
        return {ok=true, chips=u.chips}

    elseif t == "add_chips" then
        if not adminOK(db, req.admin, req.admin_password) then
            return {ok=false, msg="Unauthorized"}
        end
        local u = db.users[req.target]
        if not u then return {ok=false, msg="User not found"} end
        u.chips = u.chips + req.amount
        saveDB(db)
        return {ok=true, chips=u.chips}

    elseif t == "set_chips" then
        if not adminOK(db, req.admin, req.admin_password) then
            return {ok=false, msg="Unauthorized"}
        end
        local u = db.users[req.target]
        if not u then return {ok=false, msg="User not found"} end
        u.chips = req.amount
        saveDB(db)
        return {ok=true, chips=u.chips}

    elseif t == "update_chips" then
        -- Used by games to update chips after a round/game
        local u = db.users[req.username]
        if not u then return {ok=false} end
        -- CASINO house account can go negative (tracks net P&L)
        if u.is_casino then
            u.chips = u.chips + req.delta
        else
            u.chips = math.max(0, u.chips + req.delta)
        end
        saveDB(db)
        return {ok=true, chips=u.chips}

    elseif t == "list_users" then
        if not adminOK(db, req.admin, req.admin_password) then
            return {ok=false, msg="Unauthorized"}
        end
        local list = {}
        for name, u in pairs(db.users) do
            list[#list+1] = {username=name, chips=u.chips, is_admin=u.is_admin}
        end
        table.sort(list, function(a, b) return a.username < b.username end)
        return {ok=true, users=list}

    else
        return {ok=false, msg="Unknown command: " .. tostring(t)}
    end
end

-- ── Main ──────────────────────────────────────────────────────────
local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
if not modem then error("No wireless modem found!", 0) end
rednet.open(peripheral.getName(modem))
rednet.host(PROTOCOL, "casino_server")

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("=== CASINO DATABASE SERVER ===")
term.setTextColor(colors.green)
print("v" .. VERSION .. "  |  Ready")
term.setTextColor(colors.lightGray)
print("Protocol: " .. PROTOCOL)
print("")

local db = loadDB()

-- Ensure CASINO house account exists (created once, never via register)
if not db.users["CASINO"] then
    db.users["CASINO"] = {
        password  = "",
        chips     = 0,
        is_admin  = false,
        is_casino = true,
    }
    saveDB(db)
    term.setTextColor(colors.yellow)
    print("Created CASINO house account")
end

local userCount = 0
for _ in pairs(db.users) do userCount = userCount + 1 end
term.setTextColor(colors.white)
print("Users in DB: " .. userCount)
if next(db.users) == nil then
    term.setTextColor(colors.cyan)
    print("Empty DB - first registered user becomes admin!")
end
term.setTextColor(colors.gray)
print(string.rep("-", term.getSize()))
term.setTextColor(colors.white)
print("")

local reqCount = 0
while true do
    local sender, msg = rednet.receive(PROTOCOL)
    if type(msg) == "table" then
        reqCount = reqCount + 1
        local resp = handle(msg, db)
        rednet.send(sender, resp, PROTOCOL)

        local who  = msg.username or msg.admin or "?"
        local what = msg.type or "?"
        if resp.ok then
            term.setTextColor(colors.green)
            print("[" .. reqCount .. "] " .. who .. " -> " .. what .. " OK")
        else
            term.setTextColor(colors.red)
            print("[" .. reqCount .. "] " .. who .. " -> " .. what .. " ERROR: " .. (resp.msg or "?"))
        end
        term.setTextColor(colors.white)
    end
end
