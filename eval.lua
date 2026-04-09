-- poker/eval.lua
-- Texas Hold'em håndevaluering
-- Finner beste 5-kortshånd fra 7 kort (2 hull + 5 bordkort)

local M = {}

local NUM = {
    ["2"]=2,["3"]=3,["4"]=4,["5"]=5,["6"]=6,["7"]=7,["8"]=8,
    ["9"]=9,["10"]=10, J=11, Q=12, K=13, A=14
}

local NAMES = {
    "High Card", "One Pair", "Two Pair", "Three of a Kind",
    "Straight", "Flush", "Full House", "Four of a Kind",
    "Straight Flush", "Royal Flush"
}

-- Evaluer nøyaktig 5 kort -> (rang 1-10, tiebreaker-tabell)
local function score5(h)
    local v, s = {}, {}
    for _, c in ipairs(h) do
        v[#v + 1] = NUM[c.value]
        s[#s + 1] = c.suit
    end
    table.sort(v, function(a, b) return a > b end)

    -- Flush-sjekk
    local flush = true
    for i = 2, 5 do
        if s[i] ~= s[1] then flush = false; break end
    end

    -- Straight-sjekk
    local str8 = true
    for i = 2, 5 do
        if v[i] ~= v[i - 1] - 1 then str8 = false; break end
    end
    -- A-2-3-4-5 (wheel)
    local wheel = not str8 and v[1]==14 and v[2]==5 and v[3]==4 and v[4]==3 and v[5]==2
    if wheel then str8 = true end

    -- Frekvenstelling
    local f = {}
    for _, x in ipairs(v) do f[x] = (f[x] or 0) + 1 end
    local g = {}
    for val, cnt in pairs(f) do g[#g + 1] = {val = val, cnt = cnt} end
    table.sort(g, function(a, b)
        if a.cnt ~= b.cnt then return a.cnt > b.cnt end
        return a.val > b.val
    end)

    local function G(i) return g[i] or {val = 0, cnt = 0} end
    local top = wheel and 5 or v[1]

    if flush and str8 then
        return (not wheel and v[1] == 14) and 10 or 9, {top}
    elseif G(1).cnt == 4 then
        return 8, {G(1).val, G(2).val}
    elseif G(1).cnt == 3 and G(2).cnt == 2 then
        return 7, {G(1).val, G(2).val}
    elseif flush then
        return 6, v
    elseif str8 then
        return 5, {top}
    elseif G(1).cnt == 3 then
        return 4, {G(1).val, G(2).val, G(3).val}
    elseif G(1).cnt == 2 and G(2).cnt == 2 then
        return 3, {G(1).val, G(2).val, G(3).val}
    elseif G(1).cnt == 2 then
        return 2, {G(1).val, G(2).val, G(3).val, G(4).val}
    else
        return 1, v
    end
end

-- Sjekk om (r1,t1) er bedre enn (r2,t2)
local function isBetter(r1, t1, r2, t2)
    if r1 ~= r2 then return r1 > r2 end
    for i = 1, math.max(#t1, #t2) do
        local a, b = t1[i] or 0, t2[i] or 0
        if a ~= b then return a > b end
    end
    return false
end

-- Finn beste 5-kortshånd fra liste med kort (7 for hold'em)
function M.best(allCards)
    local n = #allCards
    if n < 5 then return 0, {}, "Ikke nok kort" end

    local br, bt = 0, {}
    -- Iterer over alle kombinasjoner av 5 fra n
    for i = 1, n - 4 do
    for j = i+1, n - 3 do
    for k = j+1, n - 2 do
    for l = k+1, n - 1 do
    for m = l+1, n do
        local combo = {allCards[i], allCards[j], allCards[k], allCards[l], allCards[m]}
        local r, t = score5(combo)
        if isBetter(r, t, br, bt) then br, bt = r, t end
    end end end end end

    return br, bt, NAMES[br] or "Ukjent"
end

-- Sammenlign to hender: 1 = h1 vinner, -1 = h2 vinner, 0 = uavgjort
function M.compare(r1, t1, r2, t2)
    if r1 ~= r2 then return r1 > r2 and 1 or -1 end
    for i = 1, math.max(#t1, #t2) do
        local a, b = t1[i] or 0, t2[i] or 0
        if a ~= b then return a > b and 1 or -1 end
    end
    return 0
end

M.NAMES = NAMES
return M
