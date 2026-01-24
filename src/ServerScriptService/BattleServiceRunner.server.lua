-- ServerScriptService/Systems/BattleServiceRunner.server.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BattleRE = Remotes:WaitForChild("BattleRE")

local BattleService = require(script.Parent:WaitForChild("BattleService"))

local function toStr(x) return tostring(x or "") end

BattleRE.OnServerEvent:Connect(function(plr, kind, payload)
	kind = toStr(kind)
	payload = payload or {}

	if kind == "StartBattle" then
		local enemyId = toStr(payload.enemyId)
		if enemyId ~= "" then
			BattleService.StartBattle(plr, enemyId)
		end
		return
	end

	if kind == "Fight" then
		BattleService.OnPlayerPressedFight(plr)
		return
	end

	if kind == "End" then
		BattleService.EndBattle(plr, "ClientEnd")
		return
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	BattleService.EndBattle(plr, "PlayerLeaving")
end)
