-- casino/client.lua
-- Casino-app for lomme-PC (pocket computer)
-- Krev: Tradlos modem
-- Start: casino_app  (snarvei satt av install.lua)

local PROTOCOL = "casino"
local TIMEOUT  = 5

local W = term.getSize()
local session = {username=nil, chips=0, is_admin=false}

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

-- ── Auth screens ──────────────────────────────────────────────────
local function screenLogin()
    while true do
        cls()
        header("LOGG INN")
        print("")
        local username = prompt("Brukernavn")
        local password = promptPass("Passord")
        print("")
        msg("Kobler til...", colors.lightGray)
        local resp = request({type="login", username=username, password=password})
        if not resp then
            msg("Finner ikke serveren!", colors.red); waitKey()
        elseif not resp.ok then
            msg("Feil: " .. (resp.msg or "?"), colors.red); waitKey()
        else
            session.username = username
            session.chips    = resp.chips
            session.is_admin = resp.is_admin
            return
        end
    end
end

local function screenRegister()
    while true do
        cls()
        header("REGISTRER")
        print("")
        local username = prompt("Brukernavn")
        local password = promptPass("Passord")
        local confirm  = promptPass("Bekreft passord")
        print("")
        if password ~= confirm then
            msg("Passordene stemmer ikke!", colors.red); waitKey()
        elseif #username < 2 then
            msg("Brukernavn for kort!", colors.red); waitKey()
        elseif #password < 3 then
            msg("Passord for kort (min 3)!", colors.red); waitKey()
        else
            msg("Oppretter bruker...", colors.lightGray)
            local resp = request({type="register", username=username, password=password})
            if not resp then
                msg("Finner ikke serveren!", colors.red); waitKey()
            elseif not resp.ok then
                msg("Feil: " .. (resp.msg or "?"), colors.red); waitKey()
            else
                if resp.is_admin then
                    msg("Konto opprettet! Du er admin.", colors.yellow)
                else
                    msg("Konto opprettet!", colors.green)
                end
                waitKey()
                return
            end
        end
    end
end

local function screenAuth()
    while true do
        cls()
        header("CASINO")
        print("")
        msg("1. Logg inn")
        msg("2. Registrer ny bruker")
        msg("3. Avslutt")
        print("")
        term.setTextColor(colors.cyan)
        io.write("Valg: ")
        term.setTextColor(colors.white)
        local c = read()
        if c == "1" then
            screenLogin(); return
        elseif c == "2" then
            screenRegister()
            screenLogin(); return
        elseif c == "3" then
            cls(); return false
        end
    end
    return true
end

-- ── Game menu ─────────────────────────────────────────────────────
local function refreshBalance()
    local resp = request({type="get_balance", username=session.username})
    if resp and resp.ok then session.chips = resp.chips end
end

local function screenGames()
    cls()
    header("SPILL")
    print("")
    msg("1. Texas Hold'em Poker", colors.white)
    msg("2. Blackjack           (kommer snart)", colors.gray)
    msg("3. Rulett              (kommer snart)", colors.gray)
    msg("0. Tilbake", colors.white)
    print("")
    term.setTextColor(colors.cyan)
    io.write("Valg: ")
    term.setTextColor(colors.white)
    local c = read()
    if c == "1" then
        shell.run("poker/player")
        refreshBalance()
    end
end

-- ── Main menu ─────────────────────────────────────────────────────
local function screenMain()
    while true do
        refreshBalance()
        cls()
        header("CASINO")
        print("")
        term.setTextColor(colors.lightGray)
        print("  Innlogget: " .. session.username)
        term.setTextColor(colors.yellow)
        print("  Chips:     " .. session.chips .. " kr")
        if session.is_admin then
            term.setTextColor(colors.cyan)
            print("  [ADMIN]")
        end
        print("")
        term.setTextColor(colors.gray)
        print(string.rep("-", W))
        term.setTextColor(colors.white)
        print("")
        msg("1. Spill")
        msg("2. Logg ut")
        print("")
        term.setTextColor(colors.cyan)
        io.write("Valg: ")
        term.setTextColor(colors.white)
        local c = read()
        if c == "1" then
            screenGames()
        elseif c == "2" then
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
