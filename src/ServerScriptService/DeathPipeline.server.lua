-- ServerScriptService/DeathPipeline.server.lua
-- Intercepts lethal damage -> fake-death flow:
--   - Roll refusal chance
--   - If refusal: block death, play refusal cinematic (client), then iFrames
--   - Else: block death, show Death GUI (client), wait for respawn request, respawn, iFrames

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RequestRespawnRE = Remotes:WaitForChild("RequestRespawnRE")

local StartFakeDeathRE = Remotes:WaitForChild("StartFakeDeathRE")
local StartDeathRefusalRE = Remotes:WaitForChild("StartDeathRefusalRE")
local DeathRefusalFinishedRE = Remotes:WaitForChild("DeathRefusalFinishedRE")

local RNG = Random.new()

local CFG = {
	-- Chance to go into "refuse death" cinematic path
	RefusalChance = 0.50, -- debugging

	-- Cooldowns / safety
	LethalIncidentCooldown = 2.0,   -- prevents killbrick spam loops
	SequenceHardTimeout = 18.0,     -- if client never responds, we unlock anyway

	-- iFrames
	PreSequenceIFrames = 0.25,      -- tiny buffer right as the hit happens
	PostRespawnIFrames = 3.0,       -- after real respawn
	PostRefusalIFrames = 3.0,       -- after refusal cinematic ends

	-- While "fake dead", keep them at least at this HP
	MinHealth = 1,
}

-- Per-player state
local lethalCooldownUntil = {}   -- [player] = time
local inSequence = {}           -- [player] = true
local waitingRefusal = {}       -- [player] = true while waiting for client finished
local waitingRespawn = {}       -- [player] = true while player is on death GUI
local iframeUntil = {}          -- [player] = time

local function now() return os.clock() end

local function setIFrames(plr, seconds)
	iframeUntil[plr] = now() + seconds
end

local function hasIFrames(plr)
	local t = iframeUntil[plr]
	return t and now() < t
end

local function inLethalCooldown(plr)
	local t = lethalCooldownUntil[plr]
	return t and now() < t
end

local function startLethalCooldown(plr)
	lethalCooldownUntil[plr] = now() + CFG.LethalIncidentCooldown
end

local function clampAlive(hum)
	if not hum or hum.Parent == nil then return end
	if hum.Health <= 0 then hum.Health = CFG.MinHealth end
	if hum.Health < CFG.MinHealth then hum.Health = CFG.MinHealth end
end

local function lockCharacter(plr, lock)
	local char = plr.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- Attribute is handy for debugging / future checks
	hum:SetAttribute("FakeDeadLocked", lock and true or false)

	-- "Dead" behavior (no movement)
	if lock then
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.AutoRotate = false
	else
		-- restore defaults-ish (your game may override anyway)
		hum.WalkSpeed = 16
		hum.JumpPower = 50
		hum.AutoRotate = true
	end
end

local function beginSequence(plr)
	inSequence[plr] = true
	setIFrames(plr, CFG.PreSequenceIFrames)
	lockCharacter(plr, true)
end

local function endSequence(plr)
	inSequence[plr] = nil
	waitingRefusal[plr] = nil
	waitingRespawn[plr] = nil
	lockCharacter(plr, false)
end

-- Client finished refusal cinematic
DeathRefusalFinishedRE.OnServerEvent:Connect(function(plr)
	if waitingRefusal[plr] then
		waitingRefusal[plr] = false
	end
end)

-- Respawn requested from GUI
RequestRespawnRE.OnServerEvent:Connect(function(plr, tag)
	-- Only accept if they’re actually in the fake-death GUI flow
	if not waitingRespawn[plr] then return end
	waitingRespawn[plr] = false

	-- Real respawn
	endSequence(plr)
	plr:LoadCharacter()

	-- Post-respawn iFrames to prevent instant re-nuke
	setIFrames(plr, CFG.PostRespawnIFrames)
end)

local function runRefusal(plr)
	waitingRefusal[plr] = true

	StartDeathRefusalRE:FireClient(plr, { tag = "DeathRefusal" })

	local t0 = now()
	while waitingRefusal[plr] and (now() - t0) < CFG.SequenceHardTimeout do
		task.wait(0.05)
	end

	-- unlock + iFrames
	endSequence(plr)
	setIFrames(plr, CFG.PostRefusalIFrames)
end

local function runFakeDeathGui(plr)
	waitingRespawn[plr] = true

	StartFakeDeathRE:FireClient(plr, { tag = "FakeDeath" })

	local t0 = now()
	while waitingRespawn[plr] and (now() - t0) < CFG.SequenceHardTimeout do
		task.wait(0.05)
	end

	-- If they never clicked respawn, fail-safe: unlock and give a small iframe
	if waitingRespawn[plr] then
		waitingRespawn[plr] = false
		endSequence(plr)
		setIFrames(plr, 1.0)
	end
end

local function interceptLethal(plr)
	-- Don’t re-enter
	if inSequence[plr] then return end
	if hasIFrames(plr) then return end
	if inLethalCooldown(plr) then return end

	startLethalCooldown(plr)
	beginSequence(plr)

	-- Roll refusal
	local roll = RNG:NextNumber()
	local refuse = (roll <= CFG.RefusalChance)

	task.spawn(function()
		if refuse then
			runRefusal(plr)
		else
			runFakeDeathGui(plr)
		end
	end)
end

local function hookCharacter(plr, char)
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end

	-- Make "real death" less destructive if it somehow happens
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false

	-- Small spawn iFrames so a killbrick spawn doesn’t insta-loop
	setIFrames(plr, 1.0)

	local lastHp = hum.Health

	hum.HealthChanged:Connect(function(hp)
		-- While iFrames or inSequence, keep them alive
		if hasIFrames(plr) or inSequence[plr] then
			clampAlive(hum)
			lastHp = hum.Health
			return
		end

		-- Lethal attempt detected
		if hp <= 0.5 and lastHp > 0.5 then
			-- Immediately prevent real death
			clampAlive(hum)
			interceptLethal(plr)
		end

		lastHp = hp
	end)

	-- Backup: if Died fires anyway, just respawn normally and give iFrames
	hum.Died:Connect(function()
		-- If we're inSequence, we explicitly did NOT want real death
		if inSequence[plr] then
			task.defer(function()
				if hum and hum.Parent then
					hum.Health = hum.MaxHealth
				end
			end)
			return
		end

		task.defer(function()
			if plr.Parent then
				plr:LoadCharacter()
				setIFrames(plr, CFG.PostRespawnIFrames)
			end
		end)
	end)
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(char)
		hookCharacter(plr, char)
	end)
end)

for _, plr in ipairs(Players:GetPlayers()) do
	plr.CharacterAdded:Connect(function(char)
		hookCharacter(plr, char)
	end)
	if plr.Character then
		hookCharacter(plr, plr.Character)
	end
end
