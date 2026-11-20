-- Reckoning and Seal of Command detection under WoW: Forever's real secret-value rules. tests/mock_secrets.lua
-- applies them: in combat aura reads return nothing unless a spell is flagged never-secret, UNIT_AURA payloads are
-- secret, and proc cast events only arrive when a test switches them on. Every mode and the moves between them
-- are replayed, plus the old bug: a hidden buff read as "0 charges" and counted as every charge spent.
package.path = "./tests/?.lua;" .. package.path
local M = require("mock_wow")
M.install()
local S = require("mock_secrets").install(M)
local check = M.check
M.class = "PALADIN"
M.trees = { { 594, "Holy", 0 }, { 267, "Protection", 31 }, { 184, "Retribution", 5 } }

local ns = M.loadAddon(".", "ReckoningCheckoning")
local RC, UI = KennyReckoningCheckoning, ns.UI
M.fire("PLAYER_LOGIN")
RC.Settings().mode = "both"

local RECK, CMD = 1326084, 20424
local secretTotal = {}; M.secret[secretTotal] = true
local function startFight() M.meter = { total = secretTotal, rows = {} }; M.combat = true; M.fire("PLAYER_REGEN_DISABLED") end
local function endFight(rows, total) M.combat = false; M.meter = { total = total or 10000, rows = rows or { { 6603, 10000 } } }
  M.fire("PLAYER_REGEN_ENABLED"); M.advance(5) end
local function lines() return table.concat(UI.Lines(), "\n") end

-- 1. Strict client (restrictions on, nothing never-secret, no proc cast events): "none" mode.
check(RC.detect == "none" and not RC.auraReadable, "strict client starts in none mode")
S.gain(RECK, 2)
check(RC.chargesKnown and RC.charges == 2, "out of combat the buff is readable: 2 charges")
startFight()
S.update(RECK, 3)
check(RC.ReadCharges() == nil, "in combat a hidden buff reads as unknown, not 0")
check(not RC.chargesKnown and RC.fight.spent == 0, "hidden buff: no extra attacks counted as spent (old bug)")
UI.RefreshCharges()
check(UI.Frame().big:GetText() == "?/4", "hidden charges show ?/4")
S.drop(RECK)
S.cast(CMD) -- a cast event that does arrive (S.cast always fires; S.procCast only when switched on)
check(RC.fight.command == 1, "a cast event that does arrive is counted (switches to cast mode)")
check(RC.detect == "cast", "first plain proc cast switches to cast mode")
endFight({ { 6603, 7000 }, { CMD, 3000 } })
check(RC.lastFight.spent == 0 and RC.lastFight.spentKnown == false, "fight: extra attacks spent unknown, not 0")
check(RC.chargesKnown and RC.charges == 0, "after combat the buff is readable again: 0 charges")
check(RC.lastFight.cmd == 3000 and RC.lastFight.cmdAvg == 3000, "Command damage and average from the meter")
check(lines():find("? swings", 1, true) and lines():find("hidden by the game", 1, true), "window says spent swings are hidden")

-- 2. A truly strict client: no cast events ever (fresh saved variables).
KennyReckoningCheckoningDB.castSeen = nil
RC.EvaluateMode()
check(RC.detect == "none", "no cast seen ever: none mode")
startFight()
S.procCast(CMD); S.gain(RECK, 1); S.update(RECK, 2); S.drop(RECK)
check(RC.fight.command == 0 and RC.fight.gained == 0 and RC.fight.spent == 0, "none mode: hidden procs not counted or guessed")
endFight({ { 6603, 7000 }, { CMD, 2000 }, { 20178, 1000 } })
local f = RC.lastFight
check(f.cmd == 2000 and math.abs(f.cmdShare - 0.2) < 1e-9 and f.cmdAvg == nil, "none mode: Command damage and share from the meter, no average")
check(f.reck == 1000 and f.reckAvg == nil, "none mode: Reckoning meter line read, no average")
local text = lines()
check(text:find("Procs can't be counted on this client", 1, true), "none mode: honest note")
check(text:find("Command: ? procs", 1, true) and text:find("? gained, ? swings", 1, true), "none mode: ? instead of 0")
check(not text:find("0 procs", 1, true), "none mode: no '0 procs' shown as if counted")
startFight()
local keepAbbr = AbbreviateNumbers; AbbreviateNumbers = nil -- the mock's SetFormattedText keeps no text
UI.RenderLive(); AbbreviateNumbers = keepAbbr
check(UI.Frame().lines:GetText():find("Command ?", 1, true), "none mode: live view shows ? too")
endFight()

-- 3. Cast mode: the client sends the player's cast events for both spells.
S.castEvents = { [CMD] = true, [RECK] = true }
startFight()
S.procCast(CMD)
check(RC.detect == "cast" and RC.fight.command == 1, "cast mode: Command counted from its cast")
S.procCast(CMD); S.procCast(CMD)
check(RC.fight.command == 3, "Command procs on stored Reckoning swings at the same instant all count")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-dup", CMD)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-dup", CMD)
check(RC.fight.command == 4, "the same cast GUID twice counts once")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "Cast-x", CMD)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "pet", "Cast-y", CMD)
local sid = {}; M.secret[sid] = true
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-z", sid)
check(RC.fight.command == 4, "other units and secret spell IDs ignored")
S.procCast(RECK); S.gain(RECK, 1)
M.advance(1); S.procCast(RECK); S.update(RECK, 2)
check(RC.fight.gained == 2, "cast mode: Reckoning charges gained from casts, once each")
S.drop(RECK)
check(RC.fight.spent == 0, "cast mode: spends not guessed from a hidden buff")
endFight({ { 6603, 6000 }, { CMD, 4000 } })
f = RC.lastFight
check(f.commandKnown and f.gainsKnown and not f.spentKnown, "cast mode: what is known is recorded")
check(f.cmdAvg == 1000, "cast mode: Command average per proc")
check(lines():find("Command: 4 procs", 1, true) and lines():find("2 gained, ? swings", 1, true), "cast mode window")
check(KennyReckoningCheckoningDB.castSeen[CMD] and KennyReckoningCheckoningDB.castSeen[RECK], "remembered which casts this client sends")
startFight()
check(RC.detect == "cast", "next fight starts in cast mode")
endFight()

-- 4. Mode A: Reckoning buff flagged never-secret. Gains and spends come from the buff, casts aren't a 2nd source.
S.never[RECK] = true
startFight()
check(RC.detect == "aura" and RC.auraReadable, "never-secret buff: aura mode at fight start")
S.procCast(RECK); S.gain(RECK, 1)
M.advance(1); S.procCast(RECK); S.update(RECK, 2)
M.advance(1); S.update(RECK, 4)
check(RC.fight.gained == 4, "aura mode: gains from the stack only (no double count with casts)")
S.drop(RECK)
check(RC.fight.spent == 4 and RC.charges == 0, "aura mode: next swing spends all 4")
endFight({ { 6603, 6000 }, { 20178, 2000 } })
check(RC.lastFight.spentKnown and RC.lastFight.reckAvg == 500, "aura mode: Reckoning average per extra attack")
S.never[RECK] = nil

-- 5. Restrictions off: every aura readable.
S.restrictions = false
startFight()
check(RC.detect == "aura", "client without secret restrictions: aura mode")
S.gain(RECK, 1); S.drop(RECK)
check(RC.fight.gained == 1 and RC.fight.spent == 1, "restrictions off: buff counted")
endFight()
S.restrictions = true

-- 6. Client without ShouldSpellAuraBeSecret: in combat an empty read still means unknown.
local keepFn = C_Secrets.ShouldSpellAuraBeSecret
C_Secrets.ShouldSpellAuraBeSecret = nil
S.gain(RECK, 3)
startFight()
S.update(RECK, 4)
check(not RC.chargesKnown and RC.fight.spent == 0, "no secrecy predicate: hidden in combat, nothing spent")
endFight()
C_Secrets.ShouldSpellAuraBeSecret = keepFn
S.drop(RECK)

-- 7. /reck debug: one command, full diagnostic.
M.prints = {}
M.slash("/reck", "debug")
local out = table.concat(M.prints, "\n")
check(out:find("detection mode: cast", 1, true), "debug shows the mode")
check(out:find("secret restrictions: true", 1, true), "debug shows the restriction state")
check(out:find("1326084 Reckoning buff: secrecy 2", 1, true) and out:find("20424 Seal of Command: secrecy 2", 1, true), "debug lists each spell's secrecy")
check(out:find("cast events seen this session", 1, true), "debug says whether casts were seen")

-- 8. A client without C_Secrets or C_UnitAuras: no errors anywhere.
local keepS, keepU = C_Secrets, C_UnitAuras
C_Secrets, C_UnitAuras = nil, nil
local ok = pcall(RC.EvaluateMode)
local ok2, dl = pcall(RC.DetectionLines)
check(ok and ok2 and type(dl) == "table" and not RC.auraReadable, "missing APIs: no aura mode, no error")
startFight(); M.fire("UNIT_AURA", "player", {}); endFight()
C_Secrets, C_UnitAuras = keepS, keepU
-- 9. No UNIT_AURA at all during a hidden fight: the pre-combat count must not survive, and the stack drop seen
--    after combat must not be counted (or flashed) as extra attacks spent.
S.restrictions = true; S.never[RECK] = nil
S.gain(RECK, 3)
check(RC.chargesKnown and RC.charges == 3, "silent fight: 3 charges readable before combat")
startFight()
check(not RC.chargesKnown, "silent fight: count goes unknown when combat starts")
S.auras[RECK].applications = 1 -- spent in combat, no UNIT_AURA delivered
endFight()
check(RC.lastFight.spent == 0 and RC.lastFight.spentKnown == false, "silent fight: drop across hidden stretch not counted")
check(RC.chargesKnown and RC.charges == 1, "silent fight: count readable again after combat")
check(#ns.Core.errors == 0, "no Lua errors recorded")
M.done("ReckoningCheckoning proc detection")
