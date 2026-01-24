-- ServerScriptService/Systems/WeaponDamageService.server.lua
-- Bulletproof weapon damage router:
-- ✅ Global WeaponDamageRE
-- ✅ Server validates Phase2 + session + tool equipped + range/facing + weapon defs
-- ✅ Server applies damage via _G.BattleService.DealPhase2BattleDamage
-- ✅ Ignores everything during Player/Enemy turns (server enforced)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local WeaponDamageRE = Remotes:WaitForChild("WeaponDamageRE")

local BattleData = require(ReplicatedStorage:WaitForChild("BattleData"))

local MIN_INTERVAL = 0.10
local lastAt: {[Player]: number} = {}

local function canFire(plr: Player)
	local now = os.clock()
	local last = lastAt[plr] or 0
	if (now - last) < MIN_INTERVAL then return false end
	lastAt[plr] = now
	return true
end

local function getHRP(plr: Player): BasePart?
	local ch = plr.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

local function getEquippedToolByName(plr: Player, toolName: string): Tool?
	local ch = plr.Character
	if not ch then return nil end
	local t = ch:FindFirstChild(toolName)
	return (t and t:IsA("Tool")) and t or nil
end

local function getEnemyRoot(enemyModel: Model): BasePart?
	if enemyModel.PrimaryPart and enemyModel.PrimaryPart:IsA("BasePart") then
		return enemyModel.PrimaryPart
	end
	local hrp = enemyModel:FindFirstChild("HumanoidRootPart", true)
	if hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return enemyModel:FindFirstChildWhichIsA("BasePart", true)
end

local function doServerHitCheck(plr: Player, enemyModel: Model, range: number): boolean
	local hrp = getHRP(plr)
	if not hrp then return false end

	local enemyRoot = getEnemyRoot(enemyModel)
	if not enemyRoot then return false end

	local toEnemy = (enemyRoot.Position - hrp.Position)
	local dist = toEnemy.Magnitude
	if dist > range then return false end

	-- light facing check
	local dir = toEnemy.Unit
	local facing = hrp.CFrame.LookVector:Dot(dir)
	if facing < 0.1 and dist > (range * 0.65) then
		return false
	end

	return true
end

WeaponDamageRE.OnServerEvent:Connect(function(plr: Player, payload)
	if not plr or not plr.Parent then return end
	if typeof(payload) ~= "table" then return end
	if not canFire(plr) then return end

	local toolName = tostring(payload.toolName or payload.ToolName or "")
	if toolName == "" then return end

	-- Must have battle API
	local BS = _G.BattleService
	if not BS or not BS.CanAcceptWeaponSwing or not BS.GetEnemyModel or not BS.DealPhase2BattleDamage then
		return
	end

	-- Hard gate: ONLY during Phase2 attack window (server enforced)
	if BS.CanAcceptWeaponSwing(plr) ~= true then
		return
	end

	-- Tool must be equipped
	if not getEquippedToolByName(plr, toolName) then
		return
	end

	-- Weapon defs are server-owned
	local weaponDef = BattleData.Weapons and BattleData.Weapons[toolName]
	if not weaponDef then return end

	local dmg = tonumber(weaponDef.baseDamage) or 0
	local range = tonumber(weaponDef.range) or 10
	if dmg <= 0 then return end

	-- Must have a live enemy
	local enemyModel = BS.GetEnemyModel(plr)
	if not enemyModel or not enemyModel.Parent then
		return
	end

	-- Server hit validation
	if not doServerHitCheck(plr, enemyModel, range) then
		return
	end

	-- Apply battle-authoritative damage
	BS.DealPhase2BattleDamage(plr, dmg)
end)

Players.PlayerRemoving:Connect(function(plr)
	lastAt[plr] = nil
end)

print("[WeaponDamageService] Loaded (WeaponDamageRE -> Phase2-only server damage).")
	