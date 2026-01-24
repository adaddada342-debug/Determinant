-- ServerScriptService/Phase2BanditBrawl.server.lua
-- FINAL: One real enemy model per battle, server-owned HP via Humanoid
-- ✅ Persists across turns (pause/resume)
-- ✅ Tool hits in Phase2 can call DealDamage() with no humanoid references
-- ✅ Humanoid.Died ends battle via BattleService hook
-- ✅ Full stop destroys model so next battle spawns fresh clone

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local PhysicsService = game:GetService("PhysicsService")

local Systems = ServerScriptService:WaitForChild("Systems")
local AwakeningService = require(Systems:WaitForChild("AwakeningService"))
local BattleData = require(ReplicatedStorage:WaitForChild("BattleData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local function ensureRE(name)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new("RemoteEvent")
		r.Name = name
		r.Parent = Remotes
	end
	return r
end

local Phase2Enter = ensureRE("Phase2Enter")
local Phase2Exit  = ensureRE("Phase2Exit")

-- Arena math MUST match BattleService
local ARENA_Y = 9000
local ARENA_SPACING = 300
local function computeArenaCenter(plr: Player)
	return Vector3.new((plr.UserId % 50) * ARENA_SPACING, ARENA_Y, 0)
end

local brawlRoot = workspace:FindFirstChild("__Phase2Brawls") or Instance.new("Folder")
brawlRoot.Name = "__Phase2Brawls"
brawlRoot.Parent = workspace

-- sessions[plr] = {
--   battleId, enemyId, maxHP,
--   folder, model, hum,
--   endsAt, paused,
--   lastDamageAt
-- }
local sessions: {[Player]: any} = {}

local function enemiesFolder()
	return ReplicatedStorage:FindFirstChild("Enemies")
end

local function cloneEnemyModel(modelKey: string): Model?
	local f = enemiesFolder()
	if not f then return nil end
	local src = f:FindFirstChild(modelKey)
	if src and src:IsA("Model") then
		return src:Clone()
	end
	return nil
end

local function getOrCreateFolder(plr: Player): Folder
	local name = ("Brawl_%d"):format(plr.UserId)
	local f = brawlRoot:FindFirstChild(name)
	if f and f:IsA("Folder") then return f end
	f = Instance.new("Folder")
	f.Name = name
	f.Parent = brawlRoot
	return f
end

local function wipeFolder(folder: Instance)
	for _, c in ipairs(folder:GetChildren()) do
		c:Destroy()
	end
end

local function disableScriptsIn(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		end
	end
end

local function forcePrimaryPart(model: Model): BasePart?
	local hrp = model:FindFirstChild("HumanoidRootPart", true)
	if hrp and hrp:IsA("BasePart") then
		model.PrimaryPart = hrp
		return hrp
	end
	local any = model:FindFirstChildWhichIsA("BasePart", true)
	if any then
		model.PrimaryPart = any
		return any
	end
	return nil
end

local function unanchorAndNetServer(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = true
			d.CanTouch = true
			d.CanQuery = true
			d.CastShadow = false
			pcall(function() PhysicsService:SetPartCollisionGroup(d, "Default") end)
			pcall(function() d:SetNetworkOwner(nil) end)
		end
	end
end

local function findRootPart(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart", true)
		or model.PrimaryPart
		or model:FindFirstChildWhichIsA("BasePart", true)
end

local function snapModelTo(model: Model, cf: CFrame)
	local root = findRootPart(model)
	if not root then return end
	model:PivotTo(cf)
	root.CFrame = cf
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
end

local function ensureHumanoid(model: Model, maxHP: number, reset: boolean): Humanoid
	local hum = model:FindFirstChildWhichIsA("Humanoid", true)
	if not hum then
		hum = Instance.new("Humanoid")
		hum.Parent = model
	end
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = math.max(tonumber(maxHP) or 30, 1)
	if reset then
		hum.Health = hum.MaxHealth
	else
		if hum.Health > hum.MaxHealth then hum.Health = hum.MaxHealth end
	end
	return hum
end

local function fullStop(plr: Player, reason: string?)
	local s = sessions[plr]
	sessions[plr] = nil
	if s and s.folder and s.folder.Parent then
		s.folder:Destroy()
	end
	Phase2Exit:FireClient(plr, { reason = reason or "Ended" })
end

local function pause(plr: Player, reason: string?)
	local s = sessions[plr]
	if not s then
		Phase2Exit:FireClient(plr, { reason = reason or "Paused" })
		return
	end
	s.endsAt = 0
	Phase2Exit:FireClient(plr, { reason = reason or "Paused" })
end

-- Start(plr, enemyId, duration, battleId, maxHP)
local function start(plr: Player, enemyId: string, duration: number, battleId: string, maxHP: number)
	enemyId = tostring(enemyId or "Froggit")
	battleId = tostring(battleId or "")
	duration = math.clamp(tonumber(duration) or 5, 1, 15)

	local folder = getOrCreateFolder(plr)

	-- reuse if same battleId and model still exists
	local s = sessions[plr]
	if s and s.battleId == battleId and s.enemyId == enemyId and s.model and s.model.Parent and s.hum and s.hum.Parent then
		s.endsAt = os.clock() + duration
		Phase2Enter:FireClient(plr, { duration = duration, enemyId = enemyId, reused = true })
		return
	end

	-- new battle => full wipe so we get a fresh clone
	fullStop(plr, "NewBattle")
	folder = getOrCreateFolder(plr)
	wipeFolder(folder)

	local def = BattleData.Enemies[enemyId]
	local modelKey = (def and (def.modelName or def.id)) or enemyId
	local desiredHP = tonumber(maxHP) or (def and def.maxHP) or 30

	local model = cloneEnemyModel(modelKey)
	if not model then
		model = Instance.new("Model")
		model.Name = modelKey
		local p = Instance.new("Part")
		p.Size = Vector3.new(4, 6, 2)
		p.Anchored = false
		p.Parent = model
		model.PrimaryPart = p
	end

	model.Name = modelKey
	model.Parent = folder

	disableScriptsIn(model)
	forcePrimaryPart(model)
	unanchorAndNetServer(model)

	model:SetAttribute("__Phase2Owner", plr.UserId)
	model:SetAttribute("__BattleId", battleId)
	model:SetAttribute("__EnemyId", enemyId)

	local hum = ensureHumanoid(model, desiredHP, true)

	-- position
	local arenaCenter = computeArenaCenter(plr)
	local pos = arenaCenter + Vector3.new(0, 3, -18)
	local face = CFrame.new(pos, arenaCenter + Vector3.new(0, 3, 16))
	snapModelTo(model, face)

	sessions[plr] = {
		battleId = battleId,
		enemyId = enemyId,
		maxHP = desiredHP,
		folder = folder,
		model = model,
		hum = hum,
		endsAt = os.clock() + duration,
		lastDamageAt = 0,
	}

	-- tell BattleService which humanoid to watch
	if _G.BattleService and _G.BattleService.AttachEnemyHumanoid then
		pcall(function()
			_G.BattleService.AttachEnemyHumanoid(plr, hum, enemyId)
		end)
	end

	Phase2Enter:FireClient(plr, { duration = duration, enemyId = enemyId, reused = false })
end

local function getEnemyHumanoid(plr: Player): Humanoid?
	local s = sessions[plr]
	if not s then return nil end
	return s.hum
end

local function dealDamage(plr: Player, rawAmount: number): boolean
	local s = sessions[plr]
	if not s or not s.hum or not s.hum.Parent then return false end
	if (s.endsAt or 0) <= 0 then return false end
	if os.clock() > s.endsAt then return false end
	if s.hum.Health <= 0 then return false end

	-- rate limit (prevents tool spam)
	local now = os.clock()
	if (now - (s.lastDamageAt or 0)) < 0.08 then return false end
	s.lastDamageAt = now

	local amt = math.floor(tonumber(rawAmount) or 0)
	amt = math.clamp(amt, 1, 80)

	local mult = AwakeningService:GetOutgoingDamageMultiplier(plr, "Phase2Brawl")
	amt = math.floor(amt * mult + 0.5)
	amt = math.clamp(amt, 1, 250)

	s.hum:TakeDamage(amt)

	-- if it died, BattleService's Died hook will end the battle
	if s.hum.Health <= 0 and s.model and s.model:GetAttribute("__SoulCounted") ~= true then
		s.model:SetAttribute("__SoulCounted", true)
		AwakeningService:RecordKill(plr, { source = "Phase2Brawl", enemyId = s.enemyId })
	end

	return true
end

_G.Phase2Brawl = _G.Phase2Brawl or {}
_G.Phase2Brawl.Start = start
_G.Phase2Brawl.Stop = function(plr, reason, keepModels)
	if keepModels == nil then keepModels = true end
	if keepModels then
		pause(plr, reason)
	else
		fullStop(plr, reason)
	end
end
_G.Phase2Brawl.GetEnemyHumanoid = getEnemyHumanoid
_G.Phase2Brawl.DealDamage = dealDamage

Players.PlayerRemoving:Connect(function(plr)
	fullStop(plr, "Leave")
end)

print("[Phase2BanditBrawl] FINAL loaded (server-authoritative enemy + DealDamage API).")
