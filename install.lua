-- install.lua  (ROOT INSTALLER)
-- One command to install the entire Casino system
--
-- wget https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/install.lua
-- install

local BASE = "https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/"
local W    = term.getSize()

local function line(char, clr)
    term.setTextColor(clr or colors.gray)
    print(string.rep(char or "-", W))
end
local function ok(m)   term.setTextColor(colors.green);    print("  [OK]   " .. m) end
local function fail(m) term.setTextColor(colors.red);      print("  [FAIL] " .. m) end
local function info(m) term.setTextColor(colors.white);    print(m) end

local function download(url, dst)
    if fs.exists(dst) then fs.delete(dst) end
    local ok2 = shell.run("wget", url, dst)
    return ok2 and fs.exists(dst)
end

local function installFiles(files)
    local allOk = true
    for _, f in ipairs(files) do
        -- Ensure folder exists
        local dir = fs.getDir(f.dst)
        if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
        term.setTextColor(colors.lightGray)
        print("  " .. f.dst .. " ...")
        if download(BASE .. f.src, f.dst) then
            ok(f.dst)
        else
            fail(f.dst)
            allOk = false
        end
    end
    return allOk
end

local function shortcut(dst, target)
    local f = fs.open(dst, "w")
    f.write('shell.run("' .. target .. '")')
    f.close()
    ok("Shortcut: " .. dst)
end

-- ── Splash ────────────────────────────────────────────────────────
term.setBackgroundColor(colors.black)
term.clear(); term.setCursorPos(1, 1)
term.setTextColor(colors.yellow)
print(string.rep("=", W))
local title = "  CASINO COMPUTERCRAFT INSTALLER  "
term.setCursorPos(math.floor((W - #title) / 2) + 1, 2)
print(title)
print(string.rep("=", W))
term.setTextColor(colors.lightGray)
print("")
print("  What do you want to install?")
print("")
term.setTextColor(colors.white)
print("  1. Casino app     (pocket PC / player)")
print("  2. Admin          (cashier terminal)")
print("  3. Database       (server PC)")
print("  4. Poker table    (needs monitor + modem)")
print("  5. Roulette table (needs 4x6 monitor)")
print("  6. ALL            (installs everything)")
print("")
term.setTextColor(colors.cyan)
io.write("  Choice [1-6]: ")
term.setTextColor(colors.white)
local choice = read()
print("")

local allOk = true

-- ── Casino client ─────────────────────────────────────────────────
if choice == "1" or choice == "6" then
    line(); info("Casino client..."); line()
    allOk = installFiles({
        {src="casino/client.lua", dst="casino/client.lua"},
    }) and allOk
    shortcut("casino_app", "casino/client")
end

-- ── Admin ─────────────────────────────────────────────────────────
if choice == "2" or choice == "6" then
    line(); info("Admin / cashier..."); line()
    allOk = installFiles({
        {src="casino/admin.lua", dst="casino/admin.lua"},
    }) and allOk
    shortcut("casino_admin", "casino/admin")
end

-- ── Database ──────────────────────────────────────────────────────
if choice == "3" or choice == "6" then
    line(); info("Database server..."); line()
    allOk = installFiles({
        {src="casino/db.lua", dst="casino/db.lua"},
    }) and allOk
    shortcut("casino_db", "casino/db")
end

-- ── Poker ─────────────────────────────────────────────────────────
if choice == "4" or choice == "6" then
    line(); info("Poker..."); line()
    allOk = installFiles({
        {src="poker/cards.lua",  dst="poker/cards.lua"},
        {src="poker/eval.lua",   dst="poker/eval.lua"},
        {src="poker/dealer.lua", dst="poker/dealer.lua"},
        {src="poker/player.lua", dst="poker/player.lua"},
    }) and allOk
    shortcut("dealer", "poker/dealer")
    shortcut("player", "poker/player")
end

-- ── Roulette ──────────────────────────────────────────────────────
if choice == "5" or choice == "6" then
    line(); info("Roulette..."); line()
    allOk = installFiles({
        {src="roulette/table.lua",  dst="roulette/table.lua"},
        {src="roulette/player.lua", dst="roulette/player.lua"},
    }) and allOk
    shortcut("roulette_table",  "roulette/table")
    shortcut("roulette_player", "roulette/player")
end

-- ── Done ──────────────────────────────────────────────────────────
print("")
line("=", colors.yellow)
if allOk then
    term.setTextColor(colors.yellow)
    print("  DONE!")
    print("")
    term.setTextColor(colors.white)
    if choice == "1" or choice == "6" then print("  casino_app      <- player pocket PC") end
    if choice == "2" or choice == "6" then print("  casino_admin    <- cashier terminal") end
    if choice == "3" or choice == "6" then print("  casino_db       <- database server") end
    if choice == "4" or choice == "6" then
        print("  dealer          <- poker table PC")
        print("  player          <- poker player pocket PC")
    end
    if choice == "5" or choice == "6" then
        print("  roulette_table  <- roulette 4x6 monitor PC")
        print("  roulette_player <- roulette player pocket PC")
    end
    if choice == "3" or choice == "6" then
        print("")
        term.setTextColor(colors.cyan)
        print("  Start casino_db first!")
        print("  First registered user becomes admin.")
    end
else
    term.setTextColor(colors.red)
    print("  SOME FILES FAILED - check GitHub")
end
line("=", colors.yellow)
term.setTextColor(colors.white)
