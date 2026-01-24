-- ServerScriptService/DeathSequenceServer.server.lua
-- Server owns death interception + starts the client cutscene.
-- Client later calls FinishDeathSequenceRE with outcome + iframe duration.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StartDeathSequenceRE = Remotes:WaitForChild("StartDeathSequenceRE")   -- Server -> Client
local FinishDeathSequenceRE = Remotes:WaitForChild("FinishDeathSequenceRE") -- Client -> Server

-- === TUNING ===
local RESPAWN_DELAY_AFTER_FINISH = 0.1

-- per-player state
local state = {} :: {[Player]: {
	active: boolean,
	lastStart: number,
}}

local function ensureState(plr: Player)
	state[plr] = state[plr] or { active = false, lastStart = 0 }
	return state[plr]
end

local function giveIFrames(plr: Player, seconds: number)
	seconds = tonumber(seconds) or 0
	if seconds <= 0 then return end

	local char = plr.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- ForceField is simple + reliable for "iframes"
	local ff = Instance.new("ForceField")
	ff.Name = "__DeathIFrames"
	ff.Visible = false
	ff.Parent = char
	Debris:AddItem(ff, seconds)

	-- optional extra safety: keep them alive during iframes
	hum.Health = math.max(hum.Health, 1)
end

local function setFakeDead(plr: Player, isDead: boolean)
	plr:SetAttribute("__FakeDead", isDead)
end

local function startSequence(plr: Player, phase3: boolean, cause: string?)
	local st = ensureState(plr)
	if st.active then return end

	st.active = true
	st.lastStart = os.clock()
	setFakeDead(plr, true)

	-- IMPORTANT: fire client
	StartDeathSequenceRE:FireClient(plr, {
		phase3 = phase3 and true or false,
		cause = cause or "intercept",
	})
end

local function clearSequence(plr: Player)
	local st = ensureState(plr)
	st.active = false
	setFakeDead(plr, false)
end

local function hookCharacter(plr: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 5)
	if not hum then return end

	-- Make sure Roblox death doesn't instantly delete the character on us
	hum.BreakJointsOnDeath = false

	-- This is the key: when health would hit 0, we intercept and force "fake death"
	local intercepting = false
	hum.HealthChanged:Connect(function(hp)
		if intercepting then return end
		if hp > 0 then return end

		local st = ensureState(plr)
		if st.active then
			-- already running, keep them alive
			intercepting = true
			hum.Health = 1
			intercepting = false
			return
		end

		-- Intercept death
		intercepting = true
		hum.Health = 1
		intercepting = false

		-- Optional: lock movement while "fake dead"
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.AutoRotate = false

		-- Decide whether to phase3 here if you want (example: random chance)
		local doPhase3 = false
		-- doPhase3 = (math.random() < 0.25)

		startSequence(plr, doPhase3, "health<=0")
	end)
end

Players.PlayerAdded:Connect(function(plr)
	ensureState(plr)

	plr.CharacterAdded:Connect(function(char)
		clearSequence(plr)
		hookCharacter(plr, char)
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	state[plr] = nil
end)

-- Client says "I'm done, do outcome now"
FinishDeathSequenceRE.OnServerEvent:Connect(function(plr, payload)
	local st = ensureState(plr)
	if not st.active then
		-- ignore random calls
		return
	end

	local outcome = payload and payload.outcome or "revive"
	local postIFrames = payload and payload.postIFrames or 0

	-- restore movement if character still exists
	local char = plr.Character
	if char then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.WalkSpeed = 16
			hum.JumpPower = 50
			hum.AutoRotate = true
		end
	end

	clearSequence(plr)

	task.delay(RESPAWN_DELAY_AFTER_FINISH, function()
		-- outcome "revive": respawn them fresh
		if outcome == "revive" then
			plr:LoadCharacter()
			task.wait(0.05)
			giveIFrames(plr, postIFrames)
			return
		end

		-- outcome "empower": keep current character (no respawn), just iframes
		if outcome == "empower" then
			giveIFrames(plr, postIFrames)
			return
		end

		-- fallback
		plr:LoadCharacter()
		task.wait(0.05)
		giveIFrames(plr, postIFrames)
	end)
end)
