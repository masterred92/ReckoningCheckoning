-- Reckoning Checkoning window: a small holy-gold box. Blizzard textures and fonts only.
-- In combat the damage numbers from Blizzard's meter (and sometimes the Reckoning stack count) are secret: they go
-- straight into SetFormattedText and StatusBar values (both accept secret values) and are never compared or added.
local _, ns = ...
local C, Core = ns.Compat, ns.Core
local L = Core.L
local RC = ns.RC

local UI = {}
ns.UI = UI
local frame, db, settings, ticker
local ICON = "Interface\\Icons\\Spell_Holy_BlessingOfStrength" -- 135882, the Reckoning buff's own icon
local BAR = "Interface\\TargetingFrame\\UI-StatusBar"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local BG, EDGE = "Interface\\Tooltips\\UI-Tooltip-Background", "Interface\\Tooltips\\UI-Tooltip-Border"
local MIN_W, MIN_H, MAX_W, MAX_H = 180, 120, 480, 300
UI.DEFAULT_POINT = { "CENTER", 0, -210 }

local function fs(parent, font)
  local f = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  f:SetJustifyH("LEFT")
  return f
end

function UI.Place()
  local p = db.point or UI.DEFAULT_POINT
  frame:ClearAllPoints()
  frame:SetPoint(p[1], UIParent, p[1], p[2], p[3])
end

function UI.ApplyTheme(th)
  if not frame or not th then return end
  local fr, fg, fb = unpack(th.frame)
  local ar, ag, ab = unpack(th.accent)
  frame:SetBackdropBorderColor(fr, fg, fb, 1)
  frame.title:SetTextColor(unpack(th.title))
  frame.bar:SetStatusBarColor(ar, ag, ab)
  frame.flash:SetColorTexture(1, 0.9, 0.55, 1)
  frame.head:SetTextColor(ar, ag, ab)
  frame.rule:SetColorTexture(fr, fg, fb, 0.9)
  frame.tree:SetText(th.tree or "")
  UI.accent = { ar, ag, ab }
  UI.RefreshCharges()
end

function UI.ApplyLayout()
  frame:SetSize(settings.width, settings.height)
  frame:SetScale(settings.scale)
end

-- Shown when the setting is on and the character is a Paladin.
function UI.UpdateVisibility()
  if not frame then return end
  frame:SetShown(settings.shown and RC.ClassMatches())
end

function UI.Build(database, s)
  db, settings = database, s
  frame = CreateFrame("Frame", "KennyReckoningCheckoningFrame", UIParent, "BackdropTemplate")
  frame:SetFrameStrata("MEDIUM")
  frame:SetClampedToScreen(true)
  frame:SetBackdrop({ bgFile = BG, edgeFile = EDGE, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  frame:SetBackdropColor(0.07, 0.06, 0.05, 0.88) -- dark stone
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetResizable(true)
  frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) if not settings.locked then self:StartMoving() end end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, _, x, y = self:GetPoint()
    db.point = { p, x, y }
  end)

  local icon = frame:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ICON)
  icon:SetSize(18, 18)
  icon:SetPoint("TOPLEFT", 8, -7)
  frame.title = fs(frame, "GameFontNormal")
  frame.title:SetPoint("LEFT", icon, "RIGHT", 5, 0)
  frame.title:SetText("Reckoning Checkoning")
  frame.tree = fs(frame, "GameFontDisableSmall")
  frame.tree:SetPoint("TOPRIGHT", -9, -11)
  frame.tree:SetJustifyH("RIGHT")
  frame.title:SetPoint("RIGHT", frame.tree, "LEFT", -4, 0)
  frame.title:SetWordWrap(false)
  frame.rule = frame:CreateTexture(nil, "ARTWORK")
  frame.rule:SetHeight(1)
  frame.rule:SetPoint("TOPLEFT", 8, -28)
  frame.rule:SetPoint("TOPRIGHT", -8, -28)

  -- headline: COMMAND! / Reckoning charges
  frame.head = fs(frame, "GameFontNormalLarge")
  frame.head:SetPoint("TOPLEFT", 10, -33)
  frame.head:SetPoint("RIGHT", -80, 0)
  frame.head:SetWordWrap(false)
  -- big charge number on the right, four pips under it
  frame.big = fs(frame, "GameFontNormalHuge")
  frame.big:SetPoint("TOPRIGHT", -12, -32)
  frame.big:SetJustifyH("RIGHT")
  frame.pips = {}
  for i = 1, RC.RECK_MAX do
    local p = frame:CreateTexture(nil, "ARTWORK")
    p:SetSize(12, 6)
    p:SetPoint("TOPRIGHT", -12 - (RC.RECK_MAX - i) * 15, -58)
    frame.pips[i] = p
  end
  frame.lines = fs(frame)
  frame.lines:SetPoint("TOPLEFT", 10, -64)
  frame.lines:SetPoint("RIGHT", -10, 0)
  frame.lines:SetJustifyV("TOP")
  frame.lines:SetSpacing(2)

  frame.bar = CreateFrame("StatusBar", nil, frame)
  frame.bar:SetStatusBarTexture(BAR)
  frame.bar:SetPoint("BOTTOMLEFT", 10, 30)
  frame.bar:SetPoint("BOTTOMRIGHT", -10, 30)
  frame.bar:SetHeight(10)
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(0)
  local barBg = frame.bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints()
  barBg:SetColorTexture(0, 0, 0, 0.5)
  frame.barText = fs(frame.bar, "GameFontHighlightSmall")
  frame.barText:SetPoint("CENTER")

  local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  reset:SetSize(96, 18)
  reset:SetPoint("BOTTOMLEFT", 8, 7)
  reset:SetText(L["Reset session"])
  reset:SetScript("OnClick", function() RC.ResetSession(); Core.Print(L["session reset."]) end)
  frame.reset = reset

  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(14, 14)
  grip:SetPoint("BOTTOMRIGHT", -4, 4)
  grip:SetNormalTexture(GRIP)
  grip:SetScript("OnMouseDown", function() if not settings.locked then frame:StartSizing("BOTTOMRIGHT") end end)
  grip:SetScript("OnMouseUp", function()
    frame:StopMovingOrSizing()
    settings.width = math.floor(frame:GetWidth() + 0.5)
    settings.height = math.floor(frame:GetHeight() + 0.5)
  end)

  -- flash: the whole box lights up gold and fades over half a second
  frame.flash = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  frame.flash:SetPoint("TOPLEFT", 3, -3)
  frame.flash:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.flash:SetBlendMode("ADD")
  frame.flash:SetAlpha(0)

  UI.ApplyLayout()
  UI.Place()
  UI.ApplyTheme(RC.theme)
  UI.UpdateVisibility()
  UI.Refresh()
  return frame
end

function UI.Frame() return frame end

local flashLeft = 0
local function flashTick(_, elapsed)
  flashLeft = flashLeft - elapsed
  if flashLeft <= 0 then frame.flash:SetAlpha(0); frame:SetScript("OnUpdate", nil) return end
  frame.flash:SetAlpha(0.45 * flashLeft / 0.5)
end
local function flash()
  flashLeft = 0.5
  frame.flash:SetAlpha(0.45)
  frame:SetScript("OnUpdate", flashTick)
end

function UI.OnCommand()
  if not frame then return end
  if RC.Mode() ~= "reckoning" then frame.head:SetText(L["COMMAND!"]) end
  flash()
  UI.Refresh()
end

function UI.OnGain()
  if not frame then return end
  if RC.Mode() ~= "command" then frame.head:SetText(L["RECKONING!"]) end
  flash()
  UI.Refresh()
end

function UI.OnSpent(n)
  if not frame then return end
  if RC.Mode() ~= "command" then frame.head:SetText(("%s +%d"):format(L["RECKONING SWING!"], n)) end
  flash()
  UI.Refresh()
end

-- Big number and pips. The number accepts a secret stack count; pips need a plain one.
function UI.RefreshCharges()
  if not frame then return end
  local showReck = RC.Mode() ~= "command"
  frame.big:SetShown(showReck)
  local a = UI.accent or { 1, 0.85, 0.4 }
  for i, p in ipairs(frame.pips) do
    p:SetShown(showReck and RC.chargesKnown)
    if RC.chargesKnown and i <= RC.charges then p:SetColorTexture(a[1], a[2], a[3], 1) else p:SetColorTexture(0.25, 0.22, 0.18, 0.9) end
  end
  if not showReck then return end
  if RC.chargesKnown then frame.big:SetFormattedText("%d/%d", RC.charges, RC.RECK_MAX)
  else frame.big:SetFormattedText("%s", RC.chargesRaw) end
end

function UI.OnCombat(inCombat)
  if frame then frame.reset:SetShown(not inCombat) end -- no Reset button in combat
  if inCombat and not ticker then
    ticker = C_Timer.NewTicker(0.5, function() Core.SafeCall("live", UI.RenderLive) end)
  elseif not inCombat and ticker then
    ticker:Cancel(); ticker = nil
  end
  UI.Refresh()
end

-- Plain-number view (out of combat): last fight + session.
function UI.Lines()
  local f, s = RC.lastFight, RC.SessionStats() or {}
  local mode = RC.Mode()
  local out = {}
  local cmdOn, reckOn = mode ~= "reckoning", mode ~= "command"
  if f then
    if cmdOn then
      if f.cmd then
        out[#out + 1] = ("%s: %d %s, %s (%s), %s %s"):format(L["Command"], f.command, L["procs"], RC.Short(f.cmd), RC.Pct(f.cmdShare),
          L["avg"], f.cmdAvg and RC.Short(f.cmdAvg) or "-") .. (f.record and ("  |cffffd200" .. L["new best!"] .. "|r") or "")
      else
        out[#out + 1] = ("%s: %d %s"):format(L["Command"], f.command, L["procs"])
      end
    end
    if reckOn then
      if f.reck then
        out[#out + 1] = ("%s: %d %s, %d %s, %s (%s)"):format(L["Reckoning"], f.gained, L["gained"], f.spent, L["swings"], RC.Short(f.reck), RC.Pct(f.reckShare))
      else
        out[#out + 1] = ("%s: %d %s, %d %s"):format(L["Reckoning"], f.gained, L["gained"], f.spent, L["swings"])
      end
    end
  else
    if cmdOn then out[#out + 1] = ("%s: %d %s"):format(L["Command"], RC.fight.command, L["procs"]) end
    if reckOn then out[#out + 1] = ("%s: %d %s, %d %s"):format(L["Reckoning"], RC.fight.gained, L["gained"], RC.fight.spent, L["swings"]) end
  end
  local sess = {}
  if cmdOn then sess[#sess + 1] = ("%d %s (%s)"):format(s.command or 0, L["Command"], RC.Pct(s.cmdShare)) end
  if reckOn then sess[#sess + 1] = ("%d %s"):format(s.spent or 0, L["swings"]) end
  out[#out + 1] = ("%s: %s"):format(L["Session"], table.concat(sess, ", "))
  if cmdOn and db and db.commandSplits == false then
    out[#out + 1] = "|cffaaaaaa" .. L["No Command meter line: counting procs only."] .. "|r"
  elseif reckOn and db and db.reckSplits == false then
    out[#out + 1] = "|cffaaaaaa" .. L["No Reckoning meter line: counting procs only."] .. "|r"
  end
  return out
end

function UI.Refresh()
  if not frame then return end
  UI.RefreshCharges()
  if RC.fight.inCombat then UI.RenderLive() return end
  if not frame.head:GetText() or frame.head:GetText() == "" then frame.head:SetText(L["Light be with you"]) end
  frame.lines:SetText(table.concat(UI.Lines(), "\n"))
  local f, s = RC.lastFight, RC.SessionStats() or {}
  local share, label
  if RC.Mode() == "reckoning" then share, label = (f and f.reckShare) or s.reckShare, L["Reckoning share"]
  else share, label = (f and f.cmdShare) or s.cmdShare, L["Command share"] end
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(share or 0)
  frame.barText:SetText(label .. " " .. RC.Pct(share))
end

-- Live view (in combat). Counts are plain; damage values may be secret and are only handed to widgets.
function UI.RenderLive()
  if not frame then return end
  local f = RC.fight
  local mode = RC.Mode()
  local parts = {}
  if mode ~= "reckoning" then parts[#parts + 1] = ("%s %d"):format(L["Command"], f.command) end
  if mode ~= "command" then parts[#parts + 1] = ("%s +%d, %d %s"):format(L["Reckoning"], f.gained, f.spent, L["swings"]) end
  local head = L["Fight"] .. ": " .. table.concat(parts, "  ")
  local src = RC.LiveSource and RC.LiveSource()
  local total = src and src.totalAmount
  local cmdAmount, cmdRows = nil, 0
  if src and type(src.combatSpells) == "table" and not C.IsSecret(src.combatSpells) then
    for _, sp in ipairs(src.combatSpells) do
      local id = sp.spellID
      if not C.IsSecret(id) and RC.COMMAND_METER[id] then cmdRows = cmdRows + 1; cmdAmount = sp.totalAmount end
    end
  end
  if total ~= nil and AbbreviateNumbers and mode ~= "reckoning" and cmdRows == 1 then
    frame.lines:SetFormattedText("%s\n%s: %s   %s: %s", head, L["Command"], AbbreviateNumbers(cmdAmount), L["You"], AbbreviateNumbers(total))
    frame.bar:SetMinMaxValues(0, total)
    frame.bar:SetValue(cmdAmount)
    frame.barText:SetText(L["Command share (live)"])
  elseif total ~= nil and AbbreviateNumbers then
    frame.lines:SetFormattedText("%s\n%s: %s\n%s", head, L["You"], AbbreviateNumbers(total), L["Share after combat"])
  else
    frame.lines:SetText(head)
  end
end

UI.MIN_W, UI.MIN_H, UI.MAX_W, UI.MAX_H = MIN_W, MIN_H, MAX_W, MAX_H

-- ---------- slash command (names live in ns.SLASH, top of ReckoningCheckoning.lua) ----------
local function help()
  local c = ns.SLASH[1]
  Core.Print(c .. " show | hide | lock | unlock | resetpos | scale 0.5-2 | size <w> <h> | reset | test")
  Core.Print(c .. " mode auto|reckoning|command|both  |  sound big|every|record|off  |  soundfile theme|chime|bell|holy")
  Core.Print(c .. " meter (last fight's damage-meter lines) | theme | debug | report")
end

for i, cmd in ipairs(ns.SLASH) do _G["SLASH_KENNYRECKONINGCHECKONING" .. i] = cmd end
SlashCmdList.KENNYRECKONINGCHECKONING = function(msg)
  if not (db and frame) then return end
  local cmd, a, b = (msg or ""):lower():match("^(%S*)%s*(%S*)%s*(%S*)")
  if cmd == "show" then
    settings.shown = true
    if not RC.ClassMatches() then Core.Print(L["this box only shows on a Paladin."]) end
    UI.UpdateVisibility(); UI.Refresh()
  elseif cmd == "hide" then settings.shown = false; UI.UpdateVisibility()
  elseif cmd == "lock" then settings.locked = true; Core.Print(L["frame locked."])
  elseif cmd == "unlock" then settings.locked = false; Core.Print(L["frame unlocked."])
  elseif cmd == "resetpos" then
    db.point = nil; settings.width, settings.height, settings.scale = RC.DEFAULTS.width, RC.DEFAULTS.height, 1
    UI.ApplyLayout(); UI.Place(); Core.Print(L["frame moved back to its default spot and size."])
  elseif cmd == "scale" and tonumber(a) then
    settings.scale = math.max(0.5, math.min(2, tonumber(a))); UI.ApplyLayout()
  elseif cmd == "size" and tonumber(a) and tonumber(b) then
    settings.width = math.max(MIN_W, math.min(MAX_W, math.floor(tonumber(a))))
    settings.height = math.max(MIN_H, math.min(MAX_H, math.floor(tonumber(b))))
    UI.ApplyLayout()
  elseif cmd == "reset" then RC.ResetSession(); Core.Print(L["session reset."])
  elseif cmd == "mode" and RC.MODES[a] then settings.mode = a; frame.head:SetText(""); UI.Refresh(); Core.Print(L["mode:"] .. " " .. a)
  elseif cmd == "sound" and RC.SOUND_MODES[a] then settings.sound = a; Core.Print(L["chime:"] .. " " .. a)
  elseif cmd == "soundfile" and (a == "theme" or RC.SOUNDS[a]) then settings.soundFile = a; RC.Chime()
  elseif cmd == "test" then
    if C.InCombat() then Core.Print(L["not in combat."]) return end
    UI.OnCommand(); RC.Chime()
  elseif cmd == "theme" then
    local th = RC.UpdateTheme()
    Core.Print(L["theme"] .. ": " .. tostring(th.tree or L["class default"]) .. " (" .. RC.Mode() .. ")")
  elseif cmd == "meter" then
    if C.InCombat() then Core.Print(L["not in combat."]) return end
    local r, why = RC.ReadMeter()
    if not r then Core.Print(L["no readable meter data"] .. " (" .. tostring(why) .. ")") return end
    Core.Print(("%s %s"):format(L["your damage:"], RC.Short(r.total)))
    for i = 1, math.min(8, #r.rows) do
      local row = r.rows[i]
      local name = C_Spell and C_Spell.GetSpellName and C.Safe(C_Spell.GetSpellName(row.spellID)) or "?"
      local tag = RC.COMMAND_METER[row.spellID] and "  <- Seal of Command" or (RC.RECK_METER[row.spellID] and "  <- Reckoning" or "")
      Core.Print(("  %d  %s  %s%s"):format(row.spellID, tostring(name), RC.Short(row.amount), tag))
    end
  elseif cmd == "debug" then Core.PrintDebug()
  elseif cmd == "report" then Core.ShowReport(RC.StateLines())
  else help() end
end
