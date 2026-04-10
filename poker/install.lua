-- install.lua
-- Automatisk installasjon av Texas Hold'em Poker for ComputerCraft
-- Last ned: wget https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/poker/install.lua
-- Kjor:     install

local BASE = "https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/poker/"

local FILES = {
    {src = "cards.lua",  dst = "poker/cards.lua"},
    {src = "eval.lua",   dst = "poker/eval.lua"},
    {src = "dealer.lua", dst = "poker/dealer.lua"},
    {src = "player.lua", dst = "poker/player.lua"},
}

local SHORTCUTS = {
    {dst = "dealer", content = 'shell.run("poker/dealer")'},
    {dst = "player", content = 'shell.run("poker/player")'},
}

local W = term.getSize()

local function line(char, clr)
    term.setTextColor(clr or colors.gray)
    print(string.rep(char or "-", W))
end
local function ok(msg)   term.setTextColor(colors.green);     print("  [OK]   " .. msg) end
local function fail(msg) term.setTextColor(colors.red);       print("  [FEIL] " .. msg) end
local function info(msg) term.setTextColor(colors.white);     print(msg) end

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

-- Lag poker/-mappe
if not fs.exists("poker") then
    fs.makeDir("poker")
    ok("Opprettet mappe: poker/")
else
    info("  Mappe poker/ finnes allerede.")
end
print("")

-- Last ned filer med wget (samme som fungerte for install.lua)
info("Laster ned filer...")
line()

local allOk = true
for _, f in ipairs(FILES) do
    term.setTextColor(colors.lightGray)
    print("  " .. f.dst .. " ...")

    -- Slett gammel fil for ren nedlasting
    if fs.exists(f.dst) then fs.delete(f.dst) end

    local url = BASE .. f.src
    local success = shell.run("wget", url, f.dst)

    if success and fs.exists(f.dst) then
        ok("Lastet ned: " .. f.dst)
    else
        fail("Feilet: " .. f.dst)
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
    print("  Start med:")
    term.setTextColor(colors.cyan)
    print("    dealer   <- bordPC (trenger monitor + modem)")
    print("    player   <- spiller (lommePC)")
else
    term.setTextColor(colors.red)
    print("  NOEN FILER FEILET!")
    term.setTextColor(colors.white)
    print("  Sjekk at filene er pushet til GitHub.")
end
line("=", colors.yellow)
term.setTextColor(colors.white)
