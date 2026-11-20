package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
-- This file covers a client where the Reckoning buff is flagged never-secret ("aura" mode).
-- tests/test_proc_detection.lua covers the strict client and the moves between modes.
local S = require("mock_secrets").install(M)
S.auras = M.auras
S.never[1326084] = true
M.class = "PALADIN"
M.trees = { { 594, "Holy", 0 }, { 267, "Protection", 31 }, { 184, "Retribution", 5 } }
local ns = M.loadAddon(".", "ReckoningCheckoning")
local RC, UI = KennyReckoningCheckoning, ns.UI
local check = M.check
M.fire("PLAYER_LOGIN")
check(KennyReckoningCheckoningDB and KennyReckoningCheckoningDB.session, "saved variables set up")
check(UI.Frame() ~= nil and UI.Frame():IsShown(), "window built and shown for a Paladin")
check(UI.Frame().points[#UI.Frame().points][4] == 0 and UI.Frame().points[#UI.Frame().points][5] == -210, "default spot CENTER 0,-210")

-- theme and mode: Protection leads with Reckoning, Retribution with Command, Holy/ties show both
check(RC.theme.tree == "Protection" and RC.Mode() == "reckoning", "Protection: Reckoning mode")
M.trees = { { 594, "Holy", 0 }, { 267, "Protection", 5 }, { 184, "Retribution", 31 } }
RC.UpdateTheme()
check(RC.Mode() == "command" and RC.theme.sound == 568608, "Retribution: Command mode, chime sound")
M.trees = { { 594, "Holy", 10 }, { 267, "Protection", 10 }, { 184, "Retribution", 0 } }
RC.UpdateTheme()
check(RC.theme.tree == nil and RC.Mode() == "both", "tie: class theme, both lines")
M.trees = { { 9999, "A", 0 }, { 9998, "B", 40 }, { 9997, "C", 0 } }
RC.UpdateTheme()
check(RC.Mode() == "reckoning", "unknown SkillLine IDs fall back to tree order (2nd = Protection)")
M.trees = nil; RC.UpdateTheme()
check(RC.Mode() == "both", "no talent data: both lines")
for _, sl in ipairs(ns.THEME.order) do check(ns.THEME.trees[sl], "tree " .. sl .. " has an entry") end

-- Seal of Command: 20424 counts; seal auras, other spells, other units and secret IDs do not
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 20424)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c1", 20424) -- the same cast delivered twice: deduped
check(RC.fight.command == 1, "one Command proc, duplicate cast GUID ignored")
check(UI.Frame().head:GetText() == "COMMAND!", "COMMAND! flash")
M.advance(1)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c2", 20424)
check(#M.sounds == 1 and M.sounds[1][1] == 568608, "Command streak (2 in 4s) plays the chime once")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c3", 20375)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "c4", 20424)
local secretID = {}; M.secret[secretID] = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c5", secretID)
check(RC.fight.command == 2, "seal cast, other units and secret IDs ignored")

check(RC.detect == "aura" and RC.auraReadable, "never-secret Reckoning buff: aura mode")
-- Reckoning: stack count readable. Gains come from the stack only (the cast is not a second source); a drop
-- counts extra attacks spent
M.sounds = {}
M.advance(1)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "r1", 1326084)
M.auras[1326084] = { applications = 1 }
M.fire("UNIT_AURA", "player", {})
check(RC.fight.gained == 1 and RC.charges == 1, "one charge, counted once from the stack")
M.advance(2)
M.auras[1326084] = { applications = 2 }; M.fire("UNIT_AURA", "player", {})
M.advance(2)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "r2", 1326084)
M.auras[1326084] = { applications = 3 }; M.fire("UNIT_AURA", "player", {})
check(RC.fight.gained == 3 and RC.charges == 3, "stack-only and cast-first gains each count once")
M.advance(2)
M.auras[1326084] = { applications = 4 }; M.fire("UNIT_AURA", "player", {})
check(RC.charges == 4 and #M.sounds == 1, "full store (4/4) plays the chime")
M.advance(2)
M.auras[1326084] = nil; M.fire("UNIT_AURA", "player", {})
check(RC.fight.spent == 4 and RC.charges == 0, "next swing spends all 4 stored attacks")
-- stack count secret: number goes to the widget as is, nothing counted from it
local secretApps = setmetatable({}, { __tostring = function() return "SECRET" end }); M.secret[secretApps] = true
M.auras[1326084] = { applications = secretApps }; M.fire("UNIT_AURA", "player", {})
check(RC.chargesKnown == false and RC.fight.spent == 4, "secret stack count: nothing spent or guessed")
M.advance(1)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "r3", 1326084)
check(RC.fight.gained == 4 and RC.fight.blind, "secret stack count: no gain guessed, fight marked blind")
UI.RefreshCharges()
check(true, "secret charge number rendered without maths")
-- live view with secret meter values: no maths, no error
local secretTotal = setmetatable({}, { __tostring = function() return "SECRET" end }); M.secret[secretTotal] = true
M.meter = { total = secretTotal, rows = { { 6603, secretTotal }, { 20424, secretTotal } } }
UI.RenderLive()
check(true, "live render with secret values")
check(UI.Frame().reset.shown == false, "Reset button hidden in combat")

-- fight ends: meter readable, Command line present, Reckoning has none
M.auras[1326084] = nil
M.combat = false
M.meter = { total = 10000, rows = { { 6603, 7000 }, { 20424, 3000 } } }
M.fire("PLAYER_REGEN_ENABLED")
M.advance(1)
local f = RC.lastFight
check(f and f.command == 2 and f.cmd == 3000 and math.abs(f.cmdShare - 0.3) < 1e-9 and f.cmdAvg == 1500, "fight: Command damage, share, avg per proc")
check(f.reck == nil and f.spent == 4, "no Reckoning meter line: swings counted, no damage made up")
check(UI.Frame().reset.shown == true, "Reset button back after combat")
check(KennyReckoningCheckoningDB.commandSplits == true and KennyReckoningCheckoningDB.reckSplits == false, "learned which lines the meter has")
local s = RC.SessionStats()
check(s.command == 2 and s.spent == 4 and s.cmdDmg == 3000 and s.total == 10000, "session totals")
M.slash("/reck", "mode reckoning")
check(table.concat(UI.Lines(), "\n"):find("counting procs only", 1, true), "window says Reckoning is counting procs only")
M.slash("/reck", "mode auto")

-- a Reckoning line on the meter is used when the game lists one
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; M.advance(5)
M.auras[1326084] = { applications = 2 }; M.fire("UNIT_AURA", "player", {})
M.advance(1); M.auras[1326084] = nil; M.fire("UNIT_AURA", "player", {})
M.combat = false; M.meter = { total = 4000, rows = { { 6603, 3000 }, { 20178, 1000 } } }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(1)
check(RC.lastFight.reck == 1000 and RC.lastFight.reckAvg == 500 and math.abs(RC.lastFight.reckShare - 0.25) < 1e-9, "Reckoning meter line: damage, share, avg per extra attack")

-- meter still secret after combat: retries, then gives up without numbers
M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; M.advance(5)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c9", 20424)
M.combat = false; M.meter = { total = secretTotal, rows = {} }
M.fire("PLAYER_REGEN_ENABLED"); M.advance(10)
check(RC.lastFight and RC.lastFight.total == nil and RC.lastFight.command == 1, "secret meter: procs only, no numbers")

-- record chime on a better Command average
RC.ResetSession()
RC.Settings().sound = "record"
M.sounds = {}
for i, dmg in ipairs({ 2000, 3000 }) do
  M.fire("PLAYER_REGEN_DISABLED"); M.combat = true; M.advance(10)
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "a" .. i, 20424); M.advance(1)
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "b" .. i, 20424)
  M.combat = false; M.meter = { total = 10000, rows = { { 20424, dmg } } }
  M.fire("PLAYER_REGEN_ENABLED"); M.advance(1)
end
check(#M.sounds == 1 and RC.SessionStats().bestAvg == 1500, "record chime only when a best is beaten")
RC.Settings().sound = "big"

-- slash commands (both names work)
M.slash("/checkoning", "reset")
check(RC.SessionStats().command == 0, "/checkoning reset clears the session")
M.slash("/reck", "size 300 200")
check(RC.Settings().width == 300 and RC.Settings().height == 200, "size")
M.slash("/reck", "size 9999 1")
check(RC.Settings().width == UI.MAX_W and RC.Settings().height == UI.MIN_H, "size is clamped")
M.slash("/reck", "scale 5")
check(RC.Settings().scale == 2, "scale is clamped")
M.slash("/reck", "lock")
check(RC.Settings().locked == true, "lock")
M.slash("/reck", "mode bogus")
check(RC.Settings().mode == "auto", "unknown mode refused")
M.sounds = {}
M.slash("/reck", "soundfile bell")
check(RC.Settings().soundFile == "bell" and M.sounds[1][1] == 568154, "sound file preview")
M.slash("/reck", "sound bogus")
check(RC.Settings().sound == "big", "unknown sound mode refused")
M.prints = {}
M.slash("/reck", "meter")
check(M.printed("Seal of Command"), "meter lists lines")
M.combat = true; M.prints = {}
M.slash("/reck", "test")
check(M.printed("not in combat"), "no test preview in combat")
M.combat = false
M.slash("/reck", "resetpos")
check(KennyReckoningCheckoningDB.point == nil and RC.Settings().scale == 1, "resetpos")
M.slash("/reck", "hide")
check(not UI.Frame():IsShown(), "hide")
-- class gate: another class never sees the box
M.class = "WARRIOR"; M.prints = {}
M.slash("/reck", "show")
check(not UI.Frame():IsShown() and M.printed("only shows on a Paladin"), "hidden for non-Paladins")
M.class = "PALADIN"
M.slash("/reck", "show")
check(UI.Frame():IsShown(), "show")
M.done("ReckoningCheckoning")
