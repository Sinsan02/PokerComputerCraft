-- casino/install.lua
-- Installerer Casino-systemet for ComputerCraft
-- Last ned: wget https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/casino/install.lua
-- Kjor:     install

local CASINO_BASE = "https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/casino/"
local POKER_BASE  = "https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/poker/"

local W = term.getSize()

local function line(char, clr)
    term.setTextColor(clr or colors.gray)
    print(string.rep(char or "-", W))
end
local function ok(m)   term.setTextColor(colors.green);     print("  [OK]   " .. m) end
local function fail(m) term.setTextColor(colors.red);       print("  [FEIL] " .. m) end
local function info(m) term.setTextColor(colors.white);     print(m) end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print("=== CASINO INSTALLER ===")
term.setTextColor(colors.lightGray)
print("ComputerCraft Casino System")
line("=", colors.yellow)
print("")
info("Hva vil du installere?")
print("")
term.setTextColor(colors.white)
print("  1. Klient      (lomme-PC / spiller)")
print("  2. Admin       (kasse-terminal)")
print("  3. DB Server   (database-server)")
print("  4. Poker       (dealer-bord + spiller)")
print("  5. Alt")
print("")
term.setTextColor(colors.cyan)
io.write("Valg [1-5]: ")
term.setTextColor(colors.white)
local choice = read()
print("")

-- ── Helpers ───────────────────────────────────────────────────────
local function download(url, dst)
    if fs.exists(dst) then fs.delete(dst) end
    local success = shell.run("wget", url, dst)
    return success and fs.exists(dst)
end

local function installFiles(files, baseUrl, folder)
    if folder and not fs.exists(folder) then
        fs.makeDir(folder)
        ok("Mappe: " .. folder .. "/")
    end
    local allOk = true
    for _, f in ipairs(files) do
        term.setTextColor(colors.lightGray)
        print("  " .. f.dst .. " ...")
        if download(baseUrl .. f.src, f.dst) then
            ok(f.dst)
        else
            fail(f.dst)
            allOk = false
        end
    end
    return allOk
end

local function makeShortcut(dst, cmd)
    local f = fs.open(dst, "w")
    f.write('shell.run("' .. cmd .. '")')
    f.close()
    ok("Snarvei: " .. dst)
end

-- ── Install ───────────────────────────────────────────────────────
local allOk = true

if choice == "1" or choice == "5" then
    line(); info("Installerer klient..."); line()
    if not fs.exists("casino") then fs.makeDir("casino") end
    allOk = installFiles(
        {{src="client.lua", dst="casino/client.lua"}},
        CASINO_BASE, nil) and allOk
    makeShortcut("casino_app", "casino/client")
end

if choice == "2" or choice == "5" then
    line(); info("Installerer admin/kasse..."); line()
    if not fs.exists("casino") then fs.makeDir("casino") end
    allOk = installFiles(
        {{src="admin.lua", dst="casino/admin.lua"}},
        CASINO_BASE, nil) and allOk
    makeShortcut("casino_admin", "casino/admin")
end

if choice == "3" or choice == "5" then
    line(); info("Installerer database-server..."); line()
    if not fs.exists("casino") then fs.makeDir("casino") end
    allOk = installFiles(
        {{src="db.lua", dst="casino/db.lua"}},
        CASINO_BASE, nil) and allOk
    makeShortcut("casino_db", "casino/db")
end

if choice == "4" or choice == "5" then
    line(); info("Installerer poker..."); line()
    if not fs.exists("poker") then fs.makeDir("poker") end
    allOk = installFiles({
        {src="cards.lua",  dst="poker/cards.lua"},
        {src="eval.lua",   dst="poker/eval.lua"},
        {src="dealer.lua", dst="poker/dealer.lua"},
        {src="player.lua", dst="poker/player.lua"},
    }, POKER_BASE, nil) and allOk
    makeShortcut("dealer", "poker/dealer")
    makeShortcut("player", "poker/player")
end

-- ── Resultat ──────────────────────────────────────────────────────
print("")
line("=", colors.yellow)
if allOk then
    term.setTextColor(colors.yellow)
    print("  INSTALLASJON FULLFORT!")
    print("")
    term.setTextColor(colors.white)
    if choice == "1" or choice == "5" then print("  casino_app    <- spiller (lomme-PC)") end
    if choice == "2" or choice == "5" then print("  casino_admin  <- kasse-terminal") end
    if choice == "3" or choice == "5" then print("  casino_db     <- database-server") end
    if choice == "4" or choice == "5" then
        print("  dealer        <- poker bord-PC")
        print("  player        <- poker spiller")
    end
    if choice == "3" or choice == "5" then
        print("")
        term.setTextColor(colors.cyan)
        print("  Tips: Start casino_db forst!")
        print("  Forste bruker som registrerer seg blir admin.")
    end
else
    term.setTextColor(colors.red)
    print("  NOEN FILER FEILET - sjekk GitHub")
end
line("=", colors.yellow)
term.setTextColor(colors.white)
