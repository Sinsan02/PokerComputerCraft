-- poker/cards.lua
-- Kortpakke-bibliotek for Texas Hold'em

local M = {}

M.SUITS  = {"S", "H", "D", "C"}
M.SYM    = {S = "\5", H = "\3", D = "\4", C = "\6"}
-- \3=♥  \4=♦  \5=♣  \6=♠  (CC:Tweaked innebygde tegn)
-- Fallback tekst hvis tegnene ikke vises riktig:
-- M.SYM = {S="S", H="H", D="D", C="C"}

M.CLR    = {S = colors.white, H = colors.red, D = colors.red, C = colors.white}
M.VALS   = {"2","3","4","5","6","7","8","9","10","J","Q","K","A"}
M.NUM    = {
    ["2"]=2,["3"]=3,["4"]=4,["5"]=5,["6"]=6,["7"]=7,["8"]=8,
    ["9"]=9,["10"]=10, J=11, Q=12, K=13, A=14
}

-- Lag ny full 52-korts bunke
function M.newDeck()
    local d = {}
    for _, s in ipairs(M.SUITS) do
        for _, v in ipairs(M.VALS) do
            d[#d + 1] = {suit = s, value = v}
        end
    end
    return d
end

-- Stokk bunken (Fisher-Yates)
function M.shuffle(d)
    math.randomseed(os.time() * os.getComputerID() + math.random(9999))
    for i = #d, 2, -1 do
        local j = math.random(i)
        d[i], d[j] = d[j], d[i]
    end
end

-- Del ut øverste kort
function M.deal(d)
    return table.remove(d)
end

-- Kort til streng, f.eks. "A♥"
function M.str(c)
    if not c then return "??" end
    return c.value .. M.SYM[c.suit]
end

return M
