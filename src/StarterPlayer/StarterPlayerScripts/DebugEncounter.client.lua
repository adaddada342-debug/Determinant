-- StarterPlayerScripts/DebugEncounter.client.lua
-- Debug: force-start a battle on keypress.
-- Keys:
--   B = start battle with current enemy
--   N = next enemy in list
--   M = previous enemy in list
--   P = print current enemy
--
-- Works with your BattleService: BattleRE "StartTest"

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BattleRE = Remotes:WaitForChild("BattleRE")

local BattleData = require(ReplicatedStorage:WaitForChild("BattleData"))

-- ===== CONFIG =====
local ENABLE_IN_STUDIO_ONLY = true
local START_KEY = Enum.KeyCode.B
local NEXT_KEY  = Enum.KeyCode.N
local PREV_KEY  = Enum.KeyCode.M
local PRINT_KEY = Enum.KeyCode.P

-- If your default enemy name differs, set it here:
local DEFAULT_ENEMY = "Froggit"
-- ===================

local function getEnemyList()
	local list = {}
	for id, def in pairs(BattleData.Enemies or {}) do
		table.insert(list, tostring(def.id or id))
	end
	table.sort(list)
	return list
end

local enemies = getEnemyList()
if #enemies == 0 then
	warn("[DebugEncounter] BattleData.Enemies is empty.")
	enemies = { DEFAULT_ENEMY }
end

local index = table.find(enemies, DEFAULT_ENEMY) or 1

local function currentEnemy()
	return enemies[index] or DEFAULT_ENEMY
end

local function canRun()
	if not ENABLE_IN_STUDIO_ONLY then return true end
	return RunService:IsStudio()
end

local function startBattle(enemyId: string)
	if not canRun() then
		warn("[DebugEncounter] Disabled outside Studio.")
		return
	end
	enemyId = enemyId or currentEnemy()
	print(("[DebugEncounter] Starting battle vs %s"):format(enemyId))
	BattleRE:FireServer("StartTest", { enemyId = enemyId })
end

local function nextEnemy()
	index += 1
	if index > #enemies then index = 1 end
	print("[DebugEncounter] Enemy ->", currentEnemy())
end

local function prevEnemy()
	index -= 1
	if index < 1 then index = #enemies end
	print("[DebugEncounter] Enemy ->", currentEnemy())
end

local function printEnemy()
	print("[DebugEncounter] Current enemy:", currentEnemy())
end

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == START_KEY then
		startBattle(currentEnemy())
	elseif input.KeyCode == NEXT_KEY then
		nextEnemy()
	elseif input.KeyCode == PREV_KEY then
		prevEnemy()
	elseif input.KeyCode == PRINT_KEY then
		printEnemy()
	end
end)

print(("[DebugEncounter] Loaded. Press %s to start, %s/%s to cycle, %s to print. Current: %s")
	:format(START_KEY.Name, NEXT_KEY.Name, PREV_KEY.Name, PRINT_KEY.Name, currentEnemy()))
