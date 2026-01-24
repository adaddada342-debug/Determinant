-- ServerScriptService/DeathRefusalServer.lua
-- Intercepts lethal damage, triggers fake-death pipeline, enforces i-frames,
-- and only respawns after the client says the cinematic is finished.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestRespawnRE = Remotes:WaitForChild("RequestRespawnRE")

-- REQUIRED: create this RemoteEvent in ReplicatedStorage > Remotes
-- Name: StartFakeDeathRE
local StartFakeDeathRE = Remotes:WaitForChild("StartFakeDeathRE")

-- =========================================================
-- CONFIG
-- =========================================================
local CFG = {
	-- DEBUG: set to 0.50 while tuning, then lower it later (0.01 = 1%)
	RefusalChance = 0.50,

	-- How long the player is invincible after being "revived/respawned"
	PostRespawnIFrames = 3.5,

	-- Safety: if client never responds, fail-safe unfreezes after this many seconds
	ClientFailSafe = 18,

	-- If something hits them repeatedly (kill brick), don't allow re-trigger spam
	LethalIncidentCooldown = 4.0,
}

local RNG = Random.new()

-- =========================================================
-- STATE
-- =========================================================
local inSequence = {}       -- [player] = true while fake-death is running
local lifeLock = {}         -- [player] = true once pipeline triggered for THIS character life
local invincibleUntil = {}  -- [player] = os.clock() timestamp
local lethalCooldownUntil = {} -- [player] = os.clock() timestamp
local lastSafeHealth = {}   -- [humanoid] = last "valid" health

-- =========================================================
-- UTIL
-- =========================================================
local function now()
	return os.clock()
end

local function setIFrames(plr, seconds)
	invincibleUntil[plr] = math.max(invincibleUntil[plr] or 0, now() + seconds)
end

local function hasIFrames(plr)
	return (invincibleUntil[plr] or 0) > now()
end

local function inLethalCooldown(plr)
	return (lethalCooldownUntil[plr] or 0) > now()
end

local function startLethalCooldown(plr)
	lethalCooldownUntil[plr] = now() + CFG.LethalIncidentCooldown
end

local function freezeCharacter(plr, char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- Save originals on attributes (so we can restore cleanly)
	if hum:GetAttribute("__OldWalkSpeed") == nil then
		hum:SetAttribute("__OldWalkSpeed", hum.WalkSpeed)
	end
	if hum:GetAttribute("__OldJumpPower") == nil then
		hum:SetAttribute("__OldJumpPower", hum.JumpPower)
	end

	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.AutoRotate = false
	-- PlatformStand is dramatic and stops a lot of jank:
	hum.PlatformStand = true
end

local function unfreezeCharacter(plr, char)
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	local oldWS = hum:GetAttribute("__OldWalkSpeed")
	local oldJP = hum:GetAttribute("__OldJumpPower")
	if typeof(oldWS) == "number" then hum.WalkSpeed = oldWS else hum.WalkSpeed = 16 end
	if typeof(oldJP) == "number" then hum.JumpPower = oldJP else hum.JumpPower = 50 end
	hum.AutoRotate = true
	hum.PlatformStand = false
end

local function safeReviveHumanoid(plr, hum)
	-- Prevent real death by restoring health immediately
	if hum and hum.Parent then
		if hum.Health <= 0 then
			hum.Health = math.max(1, hum.MaxHealth * 0.2)
		end
	end
	-- During the whole cinematic, they are invincible
	setIFrames(plr, CFG.ClientFailSafe)
end

-- =========================================================
-- PIPELINE
-- =========================================================
local function triggerFakeDeath(plr, hum)
	local char = plr.Character
	if not char or not hum or hum.Parent ~= char then return end

	-- HARD BLOCKS
	if inSequence[plr] then return end
	if lifeLock[plr] then return end
	if hasIFrames(plr) then return end
	if inLethalCooldown(plr) then return end

	-- LOCK
	inSequence[plr] = true
	lifeLock[plr] = true
	startLethalCooldown(plr)

	-- Cancel death + freeze
	safeReviveHumanoid(plr, hum)
	freezeCharacter(plr, char)

	-- Roll refusal chance
	local roll = RNG:NextNumber()
	local refuse = (roll <= CFG.RefusalChance)

	print(("[DeathPipeline] %s roll=%.3f chance=%.3f refuse=%s")
		:format(plr.Name, roll, CFG.RefusalChance, tostring(refuse)))

	-- Tell client to run Stage 1/2/3
	StartFakeDeathRE:FireClient(plr, {
		mode = refuse and "REFUSE" or "RESPAWN",
		refusalChance = CFG.RefusalChance,
		roll = roll,
	})

	-- Fail-safe: if client never replies, restore control
	task.delay(CFG.ClientFailSafe, function()
		if inSequence[plr] then
			local c = plr.Character
			if c then unfreezeCharacter(plr, c) end
			inSequence[plr] = nil
			-- Still keep i-frames briefly so they don't insta-retrigger
			setIFrames(plr, 1.5)
		end
	end)
end

-- Client says "respawn now"
RequestRespawnRE.OnServerEvent:Connect(function(plr, tag)
	-- Only accept if we’re actually in a sequence
	if not inSequence[plr] then return end

	inSequence[plr] = nil

	-- Optional: verify tag
	-- if tag ~= "AfterSoulCinematic" then return end

	-- Actually respawn them (reload character)
	plr:LoadCharacter()

	-- Give post-respawn iFrames (so they don't get nuked instantly)
	setIFrames(plr, CFG.PostRespawnIFrames)
end)

-- =========================================================
-- CHARACTER HOOKS
-- =========================================================
local function hookHumanoid(plr, char, hum)
	-- reset last safe health
	lastSafeHealth[hum] = hum.Health

	hum.HealthChanged:Connect(function(hp)
		-- Always track "safe" health when not invincible
		if not hasIFrames(plr) and hp > 0 then
			lastSafeHealth[hum] = hp
		end

		-- If invincible, undo damage
		if hasIFrames(plr) then
			-- If something tries to kill them, force back up
			if hp < 1 then
				hum.Health = math.max(1, lastSafeHealth[hum] or 10)
			end
			return
		end

		-- If health dipped to lethal, trigger fake death and restore
		if hp <= 0 then
			triggerFakeDeath(plr, hum)
		end
	end)
end

local function hookCharacter(plr, char)
	-- Reset per-life lock when a new character spawns
	lifeLock[plr] = nil
	inSequence[plr] = nil

	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end

	-- Strongly reduces “real death” jank
	hum.BreakJointsOnDeath = false
	pcall(function()
		hum.RequiresNeck = false
	end)

	hookHumanoid(plr, char, hum)
	-- Give tiny spawn iFrames to avoid spawn-kill loops
	setIFrames(plr, 0.8)
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		hookCharacter(plr, char)
	end)
end)

-- Handle studio play solo
for _, plr in ipairs(Players:GetPlayers()) do
	if plr.Character then
		hookCharacter(plr, plr.Character)
	end
	plr.CharacterAdded:Connect(function(char)
		hookCharacter(plr, char)
	end)
end
