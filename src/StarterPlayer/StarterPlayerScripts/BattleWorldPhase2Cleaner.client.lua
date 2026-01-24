-- StarterPlayerScripts/BattleWorldBattleCleaner.client.lua
-- SAFE VERSION:
-- ✅ Does NOT nuke __BattleWorld every heartbeat
-- ✅ Only cleans once when the battle ends

local Players = game:GetService("Players")
local plr = Players.LocalPlayer
local uid = tostring(plr.UserId)

local function getPhase()
	return tostring(plr:GetAttribute("__BattlePhase") or "None")
end

local function wipe()
	local bw = workspace:FindFirstChild("__BattleWorld")
	if not bw then return end
	local mine = bw:FindFirstChild(uid)
	if mine then
		mine:Destroy()
	end
end

local wasInBattle = false

plr:GetAttributeChangedSignal("__BattlePhase"):Connect(function()
	local inBattle = (getPhase() ~= "None")
	if wasInBattle and not inBattle then
		wipe()
	end
	wasInBattle = inBattle
end)
