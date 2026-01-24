-- StarterPlayerScripts/BattleViewportPhase2Disabler.client.lua
-- SAFE VERSION:
-- ✅ Does NOT clear children
-- ✅ Does NOT fight BattleUI
-- ✅ Leaves viewport management to BattleUI

local Players = game:GetService("Players")
local plr = Players.LocalPlayer

local function getPhase(): string
	return tostring(plr:GetAttribute("__BattlePhase") or "None")
end

plr:GetAttributeChangedSignal("__BattlePhase"):Connect(function()
	-- Intentionally no-op.
	-- BattleUI already hides UI during Phase2 and rebuilds viewport on PlayerTurn.
end)

if getPhase() == "Phase2" then
	-- no-op
end
