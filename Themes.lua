-- Reckoning Checkoning theme: holy gold and white, then the talent tree with the most points. Plain data, easy to tweak.
--   frame = border colour, title = title text, accent = bars, pips, flash and highlights (hex RRGGBB),
--   sound = built-in FileDataID, mode = which headline leads (reckoning, command or both).
-- A tree entry overrides only what it lists. Trees are keyed by the client's SkillLine ID (SkillLine table,
-- build 1.60.1.70862: Holy 594, Protection 267, Retribution 184). `order` is used when an ID isn't recognised.
-- Every sound and texture here was checked to exist in build 1.60.1.70862 (see tools/verify_media.sh).
local _, ns = ...

ns.THEME = { frame = "E8C25A", title = "FFFFFF", accent = "FFE38A", sound = 568608, mode = "both", -- chime (sun)
  order = { 594, 267, 184 },
  trees = { [594] = { accent = "FFF4C2", mode = "both" },       -- Holy: pale light, both lines
            [267] = { accent = "F0C860", mode = "reckoning" },  -- Protection: Reckoning charges lead
            [184] = { accent = "FFB000", mode = "command" } } } -- Retribution: COMMAND! leads
