-- casino/admin.lua
-- Casino Kasse-terminal (Admin)
-- Krev: Tradlos modem
-- Start: casino_admin  (snarvei satt av install.lua)

local PROTOCOL = "casino"
local TIMEOUT  = 5

local W = term.getSize()
local adminUser = nil
local adminPass = nil

-- ── Rednet ────────────────────────────────────────────────────────
local function openModem()
    local modem = peripheral.find("modem", function(_, m) return m.isWireless() end)
    if not modem then error("Ingen tradlos modem!", 0) end
    rednet.open(peripheral.getName(modem))
end

local function request(msg)
    local sid = rednet.lookup(PROTOCOL)
    if not sid then return nil end
    rednet.send(sid, msg, PROTOCOL)
    local _, resp = rednet.receive(PROTOCOL, TIMEOUT)
    return resp
end

-- ── UI helpers ────────────────────────────────────────────────────
local function cls()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function header(title)
    term.setTextColor(colors.yellow)
    print("=== " .. title .. " ===")
    term.setTextColor(colors.gray)
    print(string.rep("-", W))
    term.setTextColor(colors.white)
end

local function prompt(label)
    term.setTextColor(colors.cyan)
    io.write(label .. ": ")
    term.setTextColor(colors.white)
    return read()
end

local function promptPass(label)
    term.setTextColor(colors.cyan)
    io.write(label .. ": ")
    term.setTextColor(colors.white)
    return read("*")
end

local function msg(text, clr)
    term.setTextColor(clr or colors.white)
    print(text)
    term.setTextColor(colors.white)
end

local function waitKey()
    term.setTextColor(colors.gray)
    print("\nTrykk en tast...")
    os.pullEvent("key")
end

-- ── Login ─────────────────────────────────────────────────────────
local function screenLogin()
    while true do
        cls()
        header("CASINO ADMIN")
        print("")
        msg("Logg inn med admin-bruker", colors.lightGray)
        print("")
        local u = prompt("Brukernavn")
        local p = promptPass("Passord")
        print("")
        msg("Sjekker...", colors.lightGray)
        local resp = request({type="login", username=u, password=p})
        if not resp then
            msg("Finner ikke serveren!", colors.red); waitKey()
        elseif not resp.ok then
            msg(resp.msg or "Feil passord", colors.red); waitKey()
        elseif not resp.is_admin then
            msg("Ikke admin-tilgang!", colors.red); waitKey()
        else
            adminUser = u
            adminPass = p
            return
        end
    end
end

-- ── Screens ───────────────────────────────────────────────────────
local function screenListUsers()
    cls()
    header("ALLE BRUKERE")
    print("")
    msg("Henter liste...", colors.lightGray)
    local resp = request({
        type           = "list_users",
        admin          = adminUser,
        admin_password = adminPass,
    })
    if not resp or not resp.ok then
        msg("Feil: " .. (resp and resp.msg or "serverfeil"), colors.red)
        waitKey(); return
    end
    local users = resp.users
    if #users == 0 then
        msg("Ingen brukere registrert.", colors.gray)
    else
        term.setTextColor(colors.lightGray)
        print(string.format("  %-16s  %8s  %s", "Brukernavn", "Chips", ""))
        term.setTextColor(colors.gray)
        print(string.rep("-", W))
        term.setTextColor(colors.white)
        for _, u in ipairs(users) do
            local flag = u.is_admin and "[A]" or "   "
            if u.is_admin then term.setTextColor(colors.cyan)
            else               term.setTextColor(colors.white) end
            print(string.format("  %-16s  %8d  %s", u.username, u.chips, flag))
        end
        term.setTextColor(colors.gray)
        print(string.rep("-", W))
        term.setTextColor(colors.lightGray)
        print("  [A] = admin")
    end
    waitKey()
end

local function screenAddChips()
    cls()
    header("LEGG TIL CHIPS (KJOP)")
    print("")
    msg("Bruker betaler med ekte penger -> legg til chips.", colors.lightGray)
    msg("1 chip = 1 kr", colors.lightGray)
    print("")
    local target = prompt("Brukernavn")
    local raw    = prompt("Antall chips (kr)")
    local amount = tonumber(raw)
    if not amount or amount <= 0 then
        msg("Ugyldig belop!", colors.red); waitKey(); return
    end
    print("")
    term.setTextColor(colors.yellow)
    print("  Legg til " .. amount .. " chips til " .. target .. "?")
    term.setTextColor(colors.cyan)
    io.write("  Bekreft [j/n]: ")
    term.setTextColor(colors.white)
    local confirm = read()
    if confirm ~= "j" and confirm ~= "J" then
        msg("Avbrutt.", colors.gray); waitKey(); return
    end
    local resp = request({
        type           = "add_chips",
        admin          = adminUser,
        admin_password = adminPass,
        target         = target,
        amount         = amount,
    })
    if not resp then
        msg("Serverfeil!", colors.red)
    elseif not resp.ok then
        msg("Feil: " .. (resp.msg or "?"), colors.red)
    else
        msg("OK! " .. target .. " har na " .. resp.chips .. " chips.", colors.green)
    end
    waitKey()
end

local function screenSetChips()
    cls()
    header("SETT CHIPS DIREKTE")
    print("")
    msg("Overstyrer chip-saldo til eksakt verdi.", colors.lightGray)
    print("")
    local target = prompt("Brukernavn")
    local raw    = prompt("Sett chips til")
    local amount = tonumber(raw)
    if not amount or amount < 0 then
        msg("Ugyldig belop!", colors.red); waitKey(); return
    end
    print("")
    term.setTextColor(colors.yellow)
    print("  Sett " .. target .. " sine chips til " .. amount .. "?")
    term.setTextColor(colors.cyan)
    io.write("  Bekreft [j/n]: ")
    term.setTextColor(colors.white)
    local confirm = read()
    if confirm ~= "j" and confirm ~= "J" then
        msg("Avbrutt.", colors.gray); waitKey(); return
    end
    local resp = request({
        type           = "set_chips",
        admin          = adminUser,
        admin_password = adminPass,
        target         = target,
        amount         = amount,
    })
    if not resp then
        msg("Serverfeil!", colors.red)
    elseif not resp.ok then
        msg("Feil: " .. (resp.msg or "?"), colors.red)
    else
        msg("OK! " .. target .. " har na " .. resp.chips .. " chips.", colors.green)
    end
    waitKey()
end

-- ── Main menu ─────────────────────────────────────────────────────
local function screenMain()
    while true do
        cls()
        header("CASINO ADMIN")
        print("")
        term.setTextColor(colors.lightGray)
        print("  Innlogget: " .. adminUser .. " [ADMIN]")
        print("")
        term.setTextColor(colors.gray)
        print(string.rep("-", W))
        term.setTextColor(colors.white)
        print("")
        msg("1. Se alle brukere og saldoer")
        msg("2. Legg til chips  (spiller kjoper)")
        msg("3. Sett chips      (manuell overstyring)")
        msg("4. Logg ut")
        print("")
        term.setTextColor(colors.cyan)
        io.write("Valg: ")
        term.setTextColor(colors.white)
        local c = read()
        if     c == "1" then screenListUsers()
        elseif c == "2" then screenAddChips()
        elseif c == "3" then screenSetChips()
        elseif c == "4" then adminUser = nil; adminPass = nil; return
        end
    end
end

-- ── Main ──────────────────────────────────────────────────────────
openModem()
while true do
    screenLogin()
    screenMain()
end
