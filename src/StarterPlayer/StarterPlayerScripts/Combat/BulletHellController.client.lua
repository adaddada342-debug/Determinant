-- StarterPlayerScripts/Combat/BulletHellController.client.lua
-- The ONLY BulletHellRE listener.
-- Gated by:
--  - player attribute __BattlePhase == "Enemy"
--  - payload.turnId == player attribute __EnemyTurnId

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BulletHellRE = Remotes:WaitForChild("BulletHellRE")

local BulletHell3D = require(script.Parent:WaitForChild("BulletHell3D"))

local function getPhase()
	return tostring(player:GetAttribute("__BattlePhase") or "None")
end

local function getTurnId()
	return tonumber(player:GetAttribute("__EnemyTurnId") or 0)
end

BulletHellRE.OnClientEvent:Connect(function(action, payload)
	payload = payload or {}

	if action == "Start" then
		if getPhase() ~= "Enemy" then return end
		if tonumber(payload.turnId or 0) ~= getTurnId() then return end
		if BulletHell3D:IsRunning() then return end

		BulletHell3D:Start(payload)
		return
	end

	if action == "Stop" then
		BulletHell3D:Stop(payload.reason or "Stop")
		return
	end
end)
