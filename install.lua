-- install.lua
-- Automatisk installasjon av Texas Hold'em Poker for ComputerCraft
-- Kjør med: wget run https://raw.githubusercontent.com/Sinsan02/PokerComputerCraft/main/install.lua

local BASE = "https://raw.githubusercontent.com/Sinsan02/PokerComputerCraft/main/"

local FILES = {
    {src = "poker/cards.lua",   dst = "poker/cards.lua"},
    {src = "poker/eval.lua",    dst = "poker/eval.lua"},
    {src = "poker/dealer.lua",  dst = "poker/dealer.lua"},
    {src = "poker/player.lua",  dst = "poker/player.lua"},
}

-- Snarveier i roten for enkel start
local SHORTCUTS = {
    {dst = "dealer", content = 'shell.run("poker/dealer")'},
    {dst = "player", content = 'shell.run("poker/player")'},
}

local W = term.getSize()

local function line(char, clr)
    term.setTextColor(clr or colors.gray)
    print(string.rep(char or "-", W))
end

local function ok(msg)
    term.setTextColor(colors.green)
    print("  [OK] " .. msg)
end

local function fail(msg)
    term.setTextColor(colors.red)
    print("  [FEIL] " .. msg)
end

local function info(msg)
    term.setTextColor(colors.white)
    print(msg)
end

-- =====================================================
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("=== POKER INSTALLER ===")
term.setTextColor(colors.lightGray)
print("Texas Hold'em for ComputerCraft")
line("=", colors.yellow)
print("")

-- Sjekk HTTP
if not http then
    fail("HTTP er ikke aktivert!")
    info("Aktiver http i ComputerCraft konfig og prøv igjen.")
    return
end

-- Lag poker/-mappe
if not fs.exists("poker") then
    fs.makeDir("poker")
    ok("Opprettet mappe: poker/")
else
    info("  Mappe poker/ finnes allerede.")
end
print("")

-- Last ned filer
info("Laster ned filer...")
line()

local allOk = true
for _, f in ipairs(FILES) do
    term.setTextColor(colors.lightGray)
    term.write("  " .. f.dst .. " ... ")

    local url = BASE .. f.src
    local resp = http.get(url)

    if resp then
        local data = resp.readAll()
        resp.close()

        if data and #data > 0 then
            local file = fs.open(f.dst, "w")
            file.write(data)
            file.close()
            ok("OK (" .. math.floor(#data / 1024) .. " KB)")
        else
            fail("Tom respons")
            allOk = false
        end
    else
        fail("Kunne ikke laste ned fra:\n    " .. url)
        allOk = false
    end
end

-- Lag snarveier
print("")
info("Oppretter snarveier...")
line()
for _, s in ipairs(SHORTCUTS) do
    local file = fs.open(s.dst, "w")
    file.write(s.content)
    file.close()
    ok("Snarvei: '" .. s.dst .. "'")
end

-- Resultat
print("")
line("=", colors.yellow)
if allOk then
    term.setTextColor(colors.yellow)
    print("  INSTALLASJON FULLFORT!")
    print("")
    term.setTextColor(colors.white)
    print("  Bruk:")
    term.setTextColor(colors.cyan)
    print("    dealer   <- start som bordPC (med monitor)")
    print("    player   <- start som spiller (lommePC)")
    term.setTextColor(colors.lightGray)
    print("")
    print("  Bord-PC trenger: monitor + trodlos modem")
    print("  Lomme-PC: innebygd modem (pocket computer)")
else
    term.setTextColor(colors.red)
    print("  NOEN FILER FEILET!")
    term.setTextColor(colors.white)
    print("  Sjekk nettverkstilgang og prøv igjen.")
    print("  Krever HTTP aktivert i CC-konfig.")
end
line("=", colors.yellow)
term.setTextColor(colors.white)
