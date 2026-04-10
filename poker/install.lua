-- install.lua
-- Automatic installation of Texas Hold'em Poker for ComputerCraft
-- Download: wget https://raw.githubusercontent.com/Sinsan02/CasinoComputerCraft/main/poker/install.lua
-- Run:      install

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
local function ok(msg)   term.setTextColor(colors.green); print("  [OK]   " .. msg) end
local function fail(msg) term.setTextColor(colors.red);   print("  [FAIL] " .. msg) end
local function info(msg) term.setTextColor(colors.white); print(msg) end

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

-- Create poker/ folder
if not fs.exists("poker") then
    fs.makeDir("poker")
    ok("Created folder: poker/")
else
    info("  Folder poker/ already exists.")
end
print("")

-- Download files
info("Downloading files...")
line()

local allOk = true
for _, f in ipairs(FILES) do
    term.setTextColor(colors.lightGray)
    print("  " .. f.dst .. " ...")

    if fs.exists(f.dst) then fs.delete(f.dst) end

    local url = BASE .. f.src
    local success = shell.run("wget", url, f.dst)

    if success and fs.exists(f.dst) then
        ok("Downloaded: " .. f.dst)
    else
        fail("Failed: " .. f.dst)
        allOk = false
    end
end

-- Create shortcuts
print("")
info("Creating shortcuts...")
line()
for _, s in ipairs(SHORTCUTS) do
    local file = fs.open(s.dst, "w")
    file.write(s.content)
    file.close()
    ok("Shortcut: '" .. s.dst .. "'")
end

-- Result
print("")
line("=", colors.yellow)
if allOk then
    term.setTextColor(colors.yellow)
    print("  INSTALLATION COMPLETE!")
    print("")
    term.setTextColor(colors.white)
    print("  Start with:")
    term.setTextColor(colors.cyan)
    print("    dealer   <- table PC (needs monitor + modem)")
    print("    player   <- player (pocket PC)")
else
    term.setTextColor(colors.red)
    print("  SOME FILES FAILED!")
    term.setTextColor(colors.white)
    print("  Check that files are pushed to GitHub.")
end
line("=", colors.yellow)
term.setTextColor(colors.white)
