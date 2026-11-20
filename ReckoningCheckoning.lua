-- Reckoning Checkoning: a Reckoning and Seal of Command counter for Paladins on WoW: Forever. Written from scratch (MIT).
--
-- What the client data says (wago.tools db2, build 1.60.1.70862):
--   * Reckoning talent 20177 (Protection) fills a stacking buff, 1326084 "Reckoning": CumulativeAura = 4, aura text
--     "$s1 additional attacks on next swing". Its stack count is the number of stored charges (0-4). The stored
--     swings are released together on the next melee swing, so a drop in the stack count = extra attacks spent.
--   * 20178 "Reckoning" is the older Add Extra Attacks spell (SpellEffect 19). Counted as a meter line if the game
--     ever lists it; Reckoning's extra swings otherwise land on the meter as ordinary Auto Attack.
--   * Seal of Command ranks 20375, 20915, 20918, 20919, 20920 all proc 20424 "Seal of Command" (effect 31, weapon %
--     damage). The player's UNIT_SPELLCAST_SUCCEEDED names 20424, and the meter has it as its own line.
--
-- Addons on this client get no combat log and every hit amount is a secret value, so nothing here guesses a number.
-- Damage, share and average come from Blizzard's own damage meter (C_DamageMeter) once combat ends. In combat
-- those numbers are secret and only handed to widgets. How procs and charges can be seen in combat depends on the
-- client's secret-value rules; see "proc detection" below.
local ADDON, ns = ...
local C, Core = ns.Compat, ns.Core
local L = Core.L

-- Slash commands: the first is the main one shown in help text. Change them here only.
ns.SLASH = { "/reck", "/checkoning" }

local RC = {}
KennyReckoningCheckoning = RC
ns.RC = RC

local SCHEMA = 1

RC.RECK_BUFF = 1326084
RC.RECK_MAX = 4
-- Meter lines that are Reckoning's own (if the game lists any).
RC.RECK_METER = { [1326084] = true, [20178] = true }
RC.COMMAND_PROC = 20424
RC.COMMAND_SEALS = { [20375] = 1, [20915] = 2, [20918] = 3, [20919] = 4, [20920] = 5 }
RC.COMMAND_METER = { [20424] = true }

-- Built-in sound files (FileDataIDs, from the community listfile; checked by tools/verify_media.sh). No bundled audio.
RC.SOUNDS = {
  chime = 568608, -- sound/spells/fx_chimeelemental_sun_01.ogg
  bell = 568154,  -- sound/spells/shaysbell.ogg
  holy = 569211,  -- sound/spells/holy_impactdd_uber_base.ogg
}
RC.SOUND_MODES = { big = true, every = true, record = true, off = true }
RC.MODES = { auto = true, reckoning = true, command = true, both = true }

RC.DEFAULTS = {
  shown = true, locked = false, scale = 1, width = 240, height = 150,
  sound = "big", soundFile = "theme", mode = "auto", streakProcs = 2, streakSeconds = 4,
}

local db, settings
local migrations = {} -- schema 1 is the first release

local function now() return C.Clock() end

-- blind = the charge count was hidden at some point in this fight, so extra attacks spent can't be known.
local function newFight()
  return { command = 0, gained = 0, spent = 0, start = now(), times = {}, blind = false }
end
local function newSession()
  return { command = 0, gained = 0, spent = 0, fights = 0, total = 0, cmdDmg = 0, reckDmg = 0,
    cmdMeasured = 0, reckMeasured = 0, bestAvg = 0, since = C.Now() }
end

RC.fight = newFight()
RC.lastFight = nil
RC.charges = 0          -- last plain charge count (0-4)
RC.chargesRaw = 0       -- last value from the aura (may be secret; only handed to widgets)
RC.chargesKnown = true  -- false while the buff or its stack count is hidden by the game
RC.lastEvent = nil      -- "command" or "reckoning": which headline moved last

function RC.DB() return db end
function RC.Settings() return settings end
function RC.Session() return db and db.session end

-- ---------- class ----------
function RC.ClassFile()
  return C.Safe(UnitClass and select(2, UnitClass("player")))
end
function RC.ClassMatches() return RC.ClassFile() == "PALADIN" end

-- ---------- sound ----------
function RC.Chime()
  local pick = settings and settings.soundFile or "theme"
  local id = (pick == "theme" and RC.theme and RC.theme.sound) or RC.SOUNDS[pick] or RC.SOUNDS.chime
  local ok, willPlay = pcall(PlaySoundFile, id, "Master")
  return ok and willPlay ~= false
end

-- big = a full Reckoning store (4 of 4) or a Command streak (N procs within S seconds).
local function commandStreak(t)
  local need, window = settings.streakProcs, settings.streakSeconds
  local times, n = RC.fight.times, 0
  for i = #times, 1, -1 do
    if t - times[i] <= window then n = n + 1 else break end
  end
  if n >= need then
    if RC.fight.streakUntil and t < RC.fight.streakUntil then return false end
    RC.fight.streakUntil = t + window
    return true
  end
  return false
end

-- ---------- Seal of Command ----------
function RC.OnCommand(t)
  t = t or now()
  local f = RC.fight
  f.command = f.command + 1
  f.times[#f.times + 1] = t
  if db then db.session.command = db.session.command + 1 end
  RC.lastEvent = "command"
  local mode = settings and settings.sound or RC.DEFAULTS.sound
  if mode == "every" or (mode == "big" and commandStreak(t)) then RC.Chime() end
  if ns.UI then ns.UI.OnCommand() end
  return true
end

-- ---------- Reckoning ----------
local function countGain(n)
  local f = RC.fight
  f.gained = f.gained + n
  if db then db.session.gained = db.session.gained + n end
  RC.lastEvent = "reckoning"
end

local function countSpent(n)
  if n <= 0 then return end
  local f = RC.fight
  f.spent = f.spent + n
  if db then db.session.spent = db.session.spent + n end
  RC.lastEvent = "reckoning"
  if ns.UI then ns.UI.OnSpent(n) end
end

-- One Reckoning charge from the player's 1326084 cast event (only used while the buff can't be read).
function RC.OnReckoningCast()
  countGain(1)
  if ns.UI then ns.UI.OnGain() end
  return true
end

-- ---------- proc detection ----------
-- WoW: Forever hides aura data from addons in combat (UNIT_AURA payload: SecretWhenAurasRestricted;
-- C_UnitAuras.GetPlayerAuraBySpellID: SecretWhenUnitAuraRestricted + RequiresNonSecretAura, so a hidden aura
-- returns NOTHING, which looks exactly like "no buff"). Only a spell the client flags never-secret
-- (C_Secrets.GetSpellAuraSecrecy == 0) stays readable. Whether the Reckoning buff has that flag is only known in
-- game, so the way things are counted is picked at runtime and checked again at login, at the start of every
-- fight and on /reck debug:
--   "aura": the Reckoning buff can be read in combat. Charges gained = stack count going up, extra attacks spent =
--           stack count going down. Seal of Command is not an aura, so it is always counted from cast events.
--   "cast": the client has sent the player's UNIT_SPELLCAST_SUCCEEDED for 20424 (Seal of Command) or 1326084
--           (Reckoning) with a plain spell ID. Command procs and Reckoning charges gained are counted from those.
--           Extra attacks spent can't be seen in this mode and are shown as "?", never as 0.
--   "none": neither works. The window says procs can't be counted here; damage still comes from the game's meter
--           after the fight, when the meter lists Seal of Command or Reckoning as their own lines.
-- Each count has exactly one source (Reckoning gains: buff if readable, else cast), so one proc never counts
-- twice and no time-based dedupe is needed: Seal of Command procs on the stored Reckoning swings all count.
RC.PROBE = { RC.RECK_BUFF, RC.COMMAND_PROC }
RC.secrecy = {}          -- spellID -> 0 never / 1 always / 2 contextually secret, nil = unknown
RC.restricted = nil      -- C_Secrets.HasSecretRestrictions(): true / false / nil (unknown)
RC.auraReadable = false  -- the Reckoning buff can be read in combat
RC.detect = "none"       -- "aura", "cast" or "none" (RC.Mode() is the headline choice, not this)
RC.castsSeen = { [RC.COMMAND_PROC] = 0, [RC.RECK_BUFF] = 0 }

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if not ok or C.IsSecret(v) then return nil end
  return v
end

local function auraAPI()
  return C_UnitAuras ~= nil and type(C_UnitAuras.GetPlayerAuraBySpellID) == "function"
end

-- Has this client ever sent the player's cast event for spellID (or for either spell when id is nil)?
function RC.CastSeen(id)
  local seen = db and db.castSeen
  if type(seen) ~= "table" then return false end
  if id then return seen[id] == true end
  return seen[RC.COMMAND_PROC] == true or seen[RC.RECK_BUFF] == true
end
function RC.CanCountCommand() return RC.CastSeen(RC.COMMAND_PROC) end
function RC.CanCountGains() return RC.auraReadable or RC.CastSeen(RC.RECK_BUFF) end
function RC.CanCountSpent(f) return RC.auraReadable and not (f or RC.fight).blind end

-- Work out whether the Reckoning buff is readable, then the mode. Safe on any client.
function RC.EvaluateMode()
  local S = C_Secrets
  RC.restricted = S and call(S.HasSecretRestrictions)
  -- a client with neither C_Secrets nor issecretvalue has no secret values at all
  if RC.restricted == nil and type(S) ~= "table" and issecretvalue == nil then RC.restricted = false end
  for _, id in ipairs(RC.PROBE) do
    local level = S and call(S.GetSpellAuraSecrecy, id)
    RC.secrecy[id] = type(level) == "number" and level or nil
  end
  RC.auraReadable = (RC.restricted == false or RC.secrecy[RC.RECK_BUFF] == 0) and auraAPI()
  RC.detect = RC.auraReadable and "aura" or (RC.CastSeen() and "cast") or "none"
  return RC.detect
end

-- Would the game hide the Reckoning buff from us right now? Then "no buff" from GetPlayerAuraBySpellID means
-- "unknown", not 0 charges.
function RC.AuraHiddenNow()
  if RC.restricted == false then return false end
  local S = C_Secrets
  local v = S and call(S.ShouldSpellAuraBeSecret, RC.RECK_BUFF)
  if v ~= nil then return v == true end
  if RC.secrecy[RC.RECK_BUFF] == 0 then return false end
  return C.InCombat() -- no answer from the client: in combat, assume hidden
end

-- Read the stored charges from the buff. Returns the plain count and the raw value, or nil when the count is
-- unknown (buff hidden, read failed or stack count secret; a secret raw count may still come back for widgets).
function RC.ReadCharges()
  if not auraAPI() then return nil, nil end
  local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, RC.RECK_BUFF)
  if not ok or C.IsSecret(aura) then return nil, nil end
  if aura == nil then
    if RC.AuraHiddenNow() then return nil, nil end -- hidden, not empty: never read this as 0 charges
    return 0, 0
  end
  if type(aura) ~= "table" then return nil, nil end
  local ok2, apps = pcall(function() return aura.applications end)
  if not ok2 then return nil, nil end
  if C.IsSecret(apps) then return nil, apps end
  apps = tonumber(apps) or 1
  if apps < 1 then apps = 1 end -- a single stack reports 0 or 1 depending on the aura
  return math.min(RC.RECK_MAX, apps), apps
end

-- Compare the new stack count with the last plain one: up = charges gained (when the buff is the gain source),
-- down = extra attacks spent. An unknown count in between breaks the chain: nothing is counted across it.
function RC.UpdateCharges()
  local c, raw = RC.ReadCharges()
  if c == nil then
    RC.chargesKnown = false
    RC.chargesRaw = raw
    if RC.fight.inCombat then RC.fight.blind = true end
    if ns.UI then ns.UI.RefreshCharges() end
    return
  end
  local before = RC.chargesKnown and RC.charges or nil
  RC.chargesKnown = true
  RC.charges, RC.chargesRaw = c, raw
  if before then
    if c > before then
      if RC.auraReadable then
        countGain(c - before)
        if ns.UI then ns.UI.OnGain() end
      end
    elseif c < before and RC.auraReadable then -- spends only from a buff the game kept visible
      countSpent(before - c)
    end
  end
  if c >= RC.RECK_MAX and before and before < RC.RECK_MAX and settings and settings.sound == "big" then RC.Chime() end
  if ns.UI then ns.UI.RefreshCharges() end
end

-- The player's own cast events for 20424 and 1326084. A secret spell ID, another unit or the same cast delivered
-- twice (same cast GUID) is ignored.
local lastCastGUID
function RC.OnSpellcast(unit, castGUID, spellID)
  if unit ~= "player" or C.IsSecret(spellID) then return end
  if spellID ~= RC.COMMAND_PROC and spellID ~= RC.RECK_BUFF then return end
  local guid = C.Safe(castGUID)
  if guid ~= nil and guid == lastCastGUID then return end
  lastCastGUID = guid
  RC.castsSeen[spellID] = RC.castsSeen[spellID] + 1
  if db then
    if type(db.castSeen) ~= "table" then db.castSeen = {} end
    db.castSeen[spellID] = true
  end
  if RC.detect == "none" then RC.detect = "cast" end
  if spellID == RC.COMMAND_PROC then RC.OnCommand()
  elseif not RC.auraReadable then RC.OnReckoningCast() -- else counted from the buff
  elseif ns.UI then ns.UI.Refresh() end
end

function RC.OnAura(unit)
  if unit ~= "player" then return end
  RC.UpdateCharges()
end

-- Diagnostic lines for /reck debug: restriction state, each spell's secrecy, the buff, cast events and the mode.
function RC.DetectionLines()
  RC.EvaluateMode()
  local S = C_Secrets
  local aura = "-"
  if auraAPI() then
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, RC.RECK_BUFF)
    aura = not ok and "error" or C.IsSecret(a) and "secret" or a ~= nil and "up"
      or (RC.AuraHiddenNow() and "no data (hidden by the game)" or "not up")
  end
  return {
    ("detection mode: %s  (aura = buff read, cast = cast events, none = can't count procs)"):format(RC.detect),
    ("secret restrictions: %s, auras secret now: %s, Reckoning buff secret now: %s, in combat: %s"):format(
      tostring(RC.restricted), tostring(S and call(S.ShouldAurasBeSecret)),
      tostring(S and call(S.ShouldSpellAuraBeSecret, RC.RECK_BUFF)), tostring(C.InCombat())),
    ("  %d Reckoning buff: secrecy %s (0 = never secret), aura %s"):format(RC.RECK_BUFF, tostring(RC.secrecy[RC.RECK_BUFF]), aura),
    ("  %d Seal of Command: secrecy %s"):format(RC.COMMAND_PROC, tostring(RC.secrecy[RC.COMMAND_PROC])),
    ("cast events seen this session: Command %d, Reckoning %d; ever: Command %s, Reckoning %s"):format(
      RC.castsSeen[RC.COMMAND_PROC], RC.castsSeen[RC.RECK_BUFF],
      tostring(RC.CastSeen(RC.COMMAND_PROC)), tostring(RC.CastSeen(RC.RECK_BUFF))),
  }
end

-- ---------- mode: which headline the box leads with ----------
-- auto: Protection (most points) leads with Reckoning, Retribution with Command, anything else shows both.
function RC.Mode()
  local m = settings and settings.mode or "auto"
  if m ~= "auto" then return m end
  return RC.theme and RC.theme.mode or "both"
end

-- ---------- Blizzard's damage meter ----------
local function playerGUID() return UnitGUID and UnitGUID("player") end

function RC.MeterAvailable()
  if not (C_DamageMeter and C_DamageMeter.IsDamageMeterAvailable) then return false, "no C_DamageMeter" end
  local ok, avail, why = pcall(C_DamageMeter.IsDamageMeterAvailable)
  if not ok then return false, tostring(avail) end
  return avail == true, why
end

function RC.MeterSource()
  if not C_DamageMeter then return nil end
  local guid = playerGUID()
  local dmg = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
  if C_DamageMeter.GetAvailableCombatSessions and C_DamageMeter.GetCombatSessionSourceFromID then
    local ok, list = pcall(C_DamageMeter.GetAvailableCombatSessions)
    local newest
    if ok and type(list) == "table" then
      for _, s in ipairs(list) do
        local id = C.SafeNumber(s.sessionID)
        if id and (not newest or id > newest) then newest = id end
      end
    end
    if newest then
      local ok2, src = pcall(C_DamageMeter.GetCombatSessionSourceFromID, newest, dmg, guid)
      if ok2 and type(src) == "table" then return src end
    end
  end
  if C_DamageMeter.GetCombatSessionSourceFromType then
    local cur = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
    local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, cur, dmg, guid)
    if ok and type(src) == "table" then return src end
  end
  return nil
end

function RC.LiveSource()
  if not (C_DamageMeter and C_DamageMeter.GetCombatSessionSourceFromType) then return nil end
  local cur = Enum and Enum.DamageMeterSessionType and Enum.DamageMeterSessionType.Current or 1
  local dmg = Enum and Enum.DamageMeterType and Enum.DamageMeterType.DamageDone or 0
  local ok, src = pcall(C_DamageMeter.GetCombatSessionSourceFromType, cur, dmg, playerGUID())
  if ok and type(src) == "table" then return src end
  return nil
end

-- Plain-number summary: { total, cmd, reck, cmdSplit, reckSplit, rows }, or nil while anything is secret.
function RC.ReadMeter(src)
  src = src or RC.MeterSource()
  if type(src) ~= "table" then return nil, "no meter data" end
  local total = C.SafeNumber(src.totalAmount)
  if not total then return nil, "secret" end
  local out = { total = total, cmd = 0, reck = 0, rows = {}, cmdSplit = false, reckSplit = false }
  for _, sp in ipairs(type(src.combatSpells) == "table" and src.combatSpells or {}) do
    local id, amount = C.SafeNumber(sp.spellID), C.SafeNumber(sp.totalAmount)
    if not (id and amount) then return nil, "secret" end
    out.rows[#out.rows + 1] = { spellID = id, amount = amount }
    if RC.COMMAND_METER[id] then out.cmd = out.cmd + amount; out.cmdSplit = true end
    if RC.RECK_METER[id] then out.reck = out.reck + amount; out.reckSplit = true end
  end
  table.sort(out.rows, function(a, b) return a.amount > b.amount end)
  return out
end

-- ---------- fights ----------
function RC.StartFight()
  RC.fight = newFight()
  RC.fight.inCombat = true
  if ns.UI then ns.UI.OnCombat(true) end
end

function RC.EndFight()
  local f = RC.fight
  f.inCombat = false
  f.duration = math.max(0, now() - f.start)
  if ns.UI then ns.UI.OnCombat(false) end
  RC.UpdateCharges()
  local tries = 0
  local function attempt()
    tries = tries + 1
    if RC.fight ~= f or f.done then return end
    local r = RC.ReadMeter()
    if r or tries >= 4 then RC.FinishFight(f, r) return end
    C_Timer.After(1, attempt)
  end
  C_Timer.After(0.5, attempt)
end

function RC.FinishFight(f, r)
  f.done = true
  local res = { command = f.command, gained = f.gained, spent = f.spent, duration = f.duration or 0,
    commandKnown = RC.CanCountCommand(), gainsKnown = RC.CanCountGains(), spentKnown = RC.CanCountSpent(f) }
  if r then
    res.total = r.total
    if r.cmdSplit then
      res.cmd = r.cmd
      res.cmdShare = r.total > 0 and r.cmd / r.total or 0
      res.cmdAvg = res.commandKnown and f.command > 0 and r.cmd / f.command or nil
    end
    if r.reckSplit then
      res.reck = r.reck
      res.reckShare = r.total > 0 and r.reck / r.total or 0
      res.reckAvg = res.spentKnown and f.spent > 0 and r.reck / f.spent or nil
    end
  end
  RC.lastFight = res
  if db and (f.command > 0 or f.gained > 0 or f.spent > 0 or (r and r.total > 0)) then
    local s = db.session
    s.fights = s.fights + 1
    if r then
      s.total = s.total + r.total
      if f.command > 0 or r.cmdSplit then db.commandSplits = r.cmdSplit end
      if f.spent > 0 or f.gained > 0 or r.reckSplit then db.reckSplits = r.reckSplit end
      if r.cmdSplit then
        s.cmdDmg = s.cmdDmg + r.cmd
        if res.commandKnown then s.cmdMeasured = s.cmdMeasured + f.command end
        if res.cmdAvg and res.cmdAvg > s.bestAvg and f.command >= 2 then
          local beaten = s.bestAvg > 0
          s.bestAvg = res.cmdAvg
          res.record = beaten
          if beaten and settings.sound == "record" then RC.Chime() end
        end
      end
      if r.reckSplit then
        s.reckDmg = s.reckDmg + r.reck
        if res.spentKnown then s.reckMeasured = s.reckMeasured + f.spent end
      end
    end
  end
  if ns.UI then ns.UI.Refresh() end
  return res
end

function RC.ResetSession()
  if not db then return end
  db.session = newSession()
  RC.lastFight = nil
  if ns.UI then ns.UI.Refresh() end
end

function RC.SessionStats()
  local s = db and db.session
  if not s then return nil end
  return {
    command = s.command, gained = s.gained, spent = s.spent, fights = s.fights, total = s.total,
    cmdDmg = s.cmdDmg, reckDmg = s.reckDmg, bestAvg = s.bestAvg,
    cmdShare = (s.total > 0 and s.cmdDmg > 0) and s.cmdDmg / s.total or nil,
    cmdAvg = s.cmdMeasured > 0 and s.cmdDmg / s.cmdMeasured or nil,
    reckShare = (s.total > 0 and s.reckDmg > 0) and s.reckDmg / s.total or nil,
    reckAvg = s.reckMeasured > 0 and s.reckDmg / s.reckMeasured or nil,
  }
end

-- ---------- theme: Paladin colours, then the talent tree with the most points ----------
-- Forever puts the three classic trees in one C_Traits tree as node groups (Blizzard_PlayerSpells/Camelot).
local function hex(h)
  h = tostring(h or "FFFFFF")
  return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255
end
RC.Hex = hex

function RC.TreePoints()
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
    and C_Traits.GetGroupDisplayInfoByTreeID and C_Traits.GetGroupCurrencyInfo) then return nil end
  local ok, configID = pcall(C_ClassTalents.GetActiveConfigID)
  configID = ok and C.SafeNumber(configID)
  if not configID then return nil end
  local ok2, cfg = pcall(C_Traits.GetConfigInfo, configID)
  local treeID = ok2 and type(cfg) == "table" and type(cfg.treeIDs) == "table" and C.SafeNumber(cfg.treeIDs[1])
  if not treeID then return nil end
  local ok3, displays = pcall(C_Traits.GetGroupDisplayInfoByTreeID, treeID)
  if not ok3 or type(displays) ~= "table" or #displays == 0 then return nil end
  local ids = {}
  for i, d in ipairs(displays) do ids[i] = d.groupID end
  local ok4, groups = pcall(C_Traits.GetGroupCurrencyInfo, configID, ids)
  if not ok4 or type(groups) ~= "table" then return nil end
  local spentBy = {}
  for _, g in ipairs(groups) do
    local cur = type(g.currencyInfos) == "table" and g.currencyInfos[1]
    local id = C.SafeNumber(g.traitNodeGroupID)
    if id and cur then spentBy[id] = C.SafeNumber(cur.spent) end
  end
  local out = {}
  for _, d in ipairs(displays) do
    out[#out + 1] = { skillLine = C.SafeNumber(d.skillLineID), order = C.SafeNumber(d.orderIndex) or #out,
      name = C.Safe(d.displayName), spent = spentBy[C.SafeNumber(d.groupID) or -1] or 0 }
  end
  table.sort(out, function(a, b) return a.order < b.order end)
  return out
end

function RC.PickTree(classTheme, points)
  if type(points) ~= "table" or not classTheme then return nil end
  local best, bestPos, second = nil, nil, -1
  for pos, t in ipairs(points) do
    if not best or t.spent > best.spent then
      if best then second = best.spent end
      best, bestPos = t, pos
    elseif t.spent > second then second = t.spent end
  end
  if not best or best.spent <= 0 or best.spent == second then return nil end
  local trees = classTheme.trees or {}
  if best.skillLine and trees[best.skillLine] then return trees[best.skillLine], best end
  local byOrder = classTheme.order and classTheme.order[bestPos]
  if byOrder and trees[byOrder] then return trees[byOrder], best end
  return nil
end

function RC.ResolveTheme(points)
  local base = ns.THEME
  local tree, info = RC.PickTree(base, points)
  local th = { tree = info and info.name, sound = tree and tree.sound or base.sound, mode = tree and tree.mode or base.mode }
  th.frame = { hex(base.frame) }
  th.accent = { hex(tree and tree.accent or base.accent) }
  th.title = { hex(base.title or base.frame) }
  return th
end

function RC.UpdateTheme()
  RC.theme = RC.ResolveTheme(RC.TreePoints())
  if ns.UI and ns.UI.ApplyTheme then ns.UI.ApplyTheme(RC.theme) end
  return RC.theme
end
RC.theme = RC.ResolveTheme(nil)

-- ---------- text helpers ----------
function RC.Short(n)
  n = C.SafeNumber(n)
  if not n then return "?" end
  if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1e4 then return ("%.1fK"):format(n / 1e3) end
  return tostring(math.floor(n + 0.5))
end
function RC.Pct(x) return x and ("%d%%"):format(math.floor(x * 100 + 0.5)) or "-" end

function RC.StateLines()
  local s = RC.SessionStats() or {}
  local avail, why = RC.MeterAvailable()
  local f = RC.lastFight
  local lines = {
    "settings: sound=" .. tostring(settings and settings.sound) .. " file=" .. tostring(settings and settings.soundFile)
      .. " mode=" .. tostring(settings and settings.mode) .. " (" .. tostring(RC.Mode()) .. ")",
    "class: " .. tostring(RC.ClassFile()) .. " / tree: " .. tostring(RC.theme and RC.theme.tree or "class default"),
    "damage meter available: " .. tostring(avail) .. (why and why ~= "" and (" (" .. tostring(why) .. ")") or ""),
    "meter lists Seal of Command: " .. tostring(db and db.commandSplits) .. ", Reckoning: " .. tostring(db and db.reckSplits),
    "charges: " .. (RC.chargesKnown and tostring(RC.charges) or "hidden by the game right now"),
    ("session: %s Command procs, %s charges gained, %s extra attacks, %s fights"):format(tostring(s.command), tostring(s.gained), tostring(s.spent), tostring(s.fights)),
    "last fight: " .. (f and ("%d Command, %d gained, %s spent, total %s"):format(f.command, f.gained,
      f.spentKnown and tostring(f.spent) or "unknown", RC.Short(f.total)) or "none"),
  }
  for _, l in ipairs(RC.DetectionLines()) do lines[#lines + 1] = l end
  return lines
end

-- ---------- events ----------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
ev:RegisterUnitEvent("UNIT_AURA", "player")
for _, e in ipairs({ "PLAYER_LOGIN", "TRAIT_CONFIG_UPDATED", "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_TALENT_UPDATE" }) do ev:RegisterEvent(e) end

local handlers = {
  PLAYER_REGEN_DISABLED = function() RC.EvaluateMode(); RC.StartFight(); RC.UpdateCharges() end,
  PLAYER_REGEN_ENABLED = function()
    RC.EndFight()
    if RC.themeStale then RC.themeStale = false; RC.UpdateTheme() end
  end,
  UNIT_SPELLCAST_SUCCEEDED = RC.OnSpellcast,
  UNIT_AURA = RC.OnAura,
  PLAYER_LOGIN = function()
    RC.EvaluateMode()
    RC.UpdateTheme()
    RC.UpdateCharges()
    if ns.UI then ns.UI.UpdateVisibility() end
  end,
}
local function talentsChanged() if C.InCombat() then RC.themeStale = true else RC.UpdateTheme() end end
handlers.TRAIT_CONFIG_UPDATED, handlers.ACTIVE_TALENT_GROUP_CHANGED, handlers.PLAYER_TALENT_UPDATE = talentsChanged, talentsChanged, talentsChanged

ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... ~= ADDON then return end
    db = Core.Migrate(KennyReckoningCheckoningDB, migrations, SCHEMA)
    db.session = db.session or newSession()
    KennyReckoningCheckoningDB = db
    settings = Core.Settings(db.settings, RC.DEFAULTS)
    if ns.UI then Core.SafeCall("build", ns.UI.Build, db, settings) end
    return
  end
  local h = handlers[event]
  if h and db then Core.SafeCall(event, h, ...) end
end)

Core.Setup({ cmd = ns.SLASH[1],
  required = { "C_DamageMeter.GetCombatSessionSourceFromType", "C_DamageMeter.GetAvailableCombatSessions",
    "C_DamageMeter.GetCombatSessionSourceFromID", "PlaySoundFile", "C_Timer.After", "UnitGUID" },
  optional = { "C_UnitAuras.GetPlayerAuraBySpellID", "C_Secrets.GetSpellAuraSecrecy", "C_Secrets.ShouldSpellAuraBeSecret",
    "C_Secrets.HasSecretRestrictions", "C_DamageMeter.IsDamageMeterAvailable", "AbbreviateNumbers",
    "C_ClassTalents.GetActiveConfigID", "C_Traits.GetGroupDisplayInfoByTreeID", "C_Traits.GetGroupCurrencyInfo" },
  db = function() return db end,
  firstRun = { L["Reckoning and Seal of Command counter ready. Drag the box to move it; type %s for options."]:format(ns.SLASH[1]) },
  debugLines = function() return RC.StateLines() end })
