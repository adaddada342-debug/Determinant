-- ServerScriptService/RespawnServer.server.lua
-- SINGLE AUTHORITY for death interception + client cutscene start.
-- This script MUST be the only script that fires StartDeathSequenceRE.
--
-- ✅ Respects StartMenu (CharacterAutoLoads = false)
-- ✅ Intercepts lethal damage only when GameStarted==true and InMenu~=true
-- ✅ Debounces HARD (no double-fires, no “fake then real”)
-- ✅ Refusal + Phase3 are mutually exclusive (never both)
-- ✅ No LoadCharacter unless explicitly requested AND safe (pcall)
-- ✅ Timeout failsafe: if client never responds, server revives player cleanly

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

Players.CharacterAutoLoads = false

--========================
-- REMOTES
--========================
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local StartDeathSequenceRE = Remotes:WaitForChild("StartDeathSequenceRE")   -- Server -> Client
local FinishDeathSequenceRE = Remotes:WaitForChild("FinishDeathSequenceRE") -- Client -> Server
local RequestRespawnRE = Remotes:FindFirstChild("RequestRespawnRE")

--========================
-- CONFIG VALUES (optional)
-- ReplicatedStorage/DeathConfig:
--   NumberValue Phase3Chance (0..1)
--   NumberValue RefusalChance (0..1)
--   BoolValue   ForcePhase3 (true forces phase3)
--   BoolValue   ForceRefusal (true forces refusal)
--========================
local DeathConfig = ReplicatedStorage:FindFirstChild("DeathConfig")
local Phase3ChanceValue = DeathConfig and DeathConfig:FindFirstChild("Phase3Chance")
local RefusalChanceValue = DeathConfig and DeathConfig:FindFirstChild("RefusalChance")
local ForcePhase3Value = DeathConfig and DeathConfig:FindFirstChild("ForcePhase3")
local ForceRefusalValue = DeathConfig and DeathConfig:FindFirstChild("ForceRefusal")

local function clamp01(x)
	x = tonumber(x) or 0
	if x < 0 then x = 0 end
	if x > 1 then x = 1 end
	return x
end

local function getPhase3Chance()
	return clamp01(Phase3ChanceValue and Phase3ChanceValue.Value)
end

local function getRefusalChance()
	return clamp01(RefusalChanceValue and RefusalChanceValue.Value)
end

--========================
-- SERVER TUNING
--========================
local CFG = {
	EmpowerDuration = 60,

	-- how long after sequence to prevent re-trigger (in addition to Downed flag)
	PostSequenceCooldown = 0.75,

	-- i-frames after finishing
	IFramesAfter = 3.0,
	MaxPostIFrames = 8.0,

	-- how we keep the player "alive" while downed
	DownedMinHealth = 1,

	-- if client never replies, revive them anyway
	ClientTimeout = 12.0,

	-- only use LoadCharacter if you REALLY want it
	ReviveUsesLoadCharacter = false,

	RespawnDebounce = 1.0,
}

local function now()
	return os.clock()
end

--========================
-- GAMEPLAY ACTIVE CHECK
--========================
local function isGameplayActive(plr: Player)
	return plr
		and plr.Parent
		and plr:GetAttribute("InMenu") ~= true
		and plr:GetAttribute("GameStarted") == true
end

--========================
-- IFRAMES
--========================
local function isIFramed(plr: Player)
	local t = plr:GetAttribute("IFrameUntil")
	return typeof(t) == "number" and t > now()
end

local function giveIFrames(plr: Player, seconds: number)
	seconds = math.max(0, tonumber(seconds) or 0)
	plr:SetAttribute("IFrameUntil", now() + seconds)
end

--========================
-- SAFE LOAD CHARACTER (no hard errors)
--========================
local function safeLoadCharacter(plr: Player, tag: string)
	if not plr or not plr.Parent then
		warn(("[Respawn] safeLoadCharacter aborted (player missing). tag=%s"):format(tostring(tag)))
		return false
	end
	local ok, err = pcall(function()
		plr:LoadCharacter()
	end)
	if not ok then
		warn(("[Respawn] LoadCharacter FAILED tag=%s err=%s"):format(tostring(tag), tostring(err)))
	end
	return ok
end

--========================
-- STATE
--========================
local state = {} -- [Player] = { active:boolean, token:number, cooldownUntil:number, downedGuardConn:RBXScriptConnection?, hookConns:{RBXScriptConnection}? }

local function ensureState(plr: Player)
	state[plr] = state[plr] or {
		active = false,
		token = 0,
		cooldownUntil = 0,
		downedGuardConn = nil,
		hookConns = {},
	}
	return state[plr]
end

local function setDowned(plr: Player, v: boolean)
	plr:SetAttribute("Downed", v and true or false)
end

local function setDeathSequenceActive(plr: Player, v: boolean)
	plr:SetAttribute("DeathSequenceActive", v and true or false)
end

local function isDowned(plr: Player)
	return plr:GetAttribute("Downed") == true
end

--========================
-- CHARACTER LOCK / UNLOCK
--========================
local function lockCharacter(plr: Player, lock: boolean)
	local char = plr.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false

	if lock then
		if hum.Health <= 0 then hum.Health = CFG.DownedMinHealth end
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.AutoRotate = false
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.Physics) end)
	else
		if hum.WalkSpeed == 0 then hum.WalkSpeed = 16 end
		if hum.JumpPower == 0 then hum.JumpPower = 50 end
		hum.AutoRotate = true
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
	end
end

--========================
-- DOWNED GUARD (keeps them pinned + alive)
--========================
local function startDownedGuard(plr: Player)
	local st = ensureState(plr)
	if st.downedGuardConn then return end

	st.downedGuardConn = RunService.Heartbeat:Connect(function()
		if not plr.Parent then return end
		if not isDowned(plr) then return end

		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return end

		if hum.Health <= 0 then hum.Health = CFG.DownedMinHealth end
		hum.BreakJointsOnDeath = false
		hum.RequiresNeck = false
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.AutoRotate = false
	end)
end

local function stopDownedGuard(plr: Player)
	local st = ensureState(plr)
	if st.downedGuardConn then
		st.downedGuardConn:Disconnect()
		st.downedGuardConn = nil
	end
end

--========================
-- RNG (exclusive outcomes)
--========================
local RNG = Random.new()

local function forceRefusal(plr: Player)
	if ForceRefusalValue and ForceRefusalValue:IsA("BoolValue") and ForceRefusalValue.Value == true then return true end
	if plr:GetAttribute("ForceRefusal") == true then return true end
	return false
end

local function forcePhase3(plr: Player)
	if ForcePhase3Value and ForcePhase3Value:IsA("BoolValue") and ForcePhase3Value.Value == true then return true end
	if plr:GetAttribute("ForcePhase3") == true then return true end
	return false
end

local function rollRefusal(plr: Player)
	if forceRefusal(plr) then return true end
	local chance = getRefusalChance()
	if chance <= 0 then return false end
	if chance >= 1 then return true end
	return RNG:NextNumber() <= chance
end

local function rollPhase3(plr: Player)
	if forcePhase3(plr) then return true end
	local chance = getPhase3Chance()
	if chance <= 0 then return false end
	if chance >= 1 then return true end
	return RNG:NextNumber() <= chance
end

--========================
-- BEGIN SEQUENCE (single entry point)
--========================
local function beginDeathSequence(plr: Player, causeTag: string)
	if not plr or not plr.Parent then return end
	local st = ensureState(plr)

	-- gameplay gate
	if not isGameplayActive(plr) then return end

	-- hard debounce gates
	if st.active then return end
	if isDowned(plr) then return end
	if isIFramed(plr) then return end
	if now() < (st.cooldownUntil or 0) then return end

	-- must have humanoid
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	-- mark active
	st.active = true
	st.token += 1
	local token = st.token

	plr:SetAttribute("__DeathSeqToken", token)
	setDowned(plr, true)
	setDeathSequenceActive(plr, true)

	-- keep alive + lock
	if hum.Health <= 0 then hum.Health = CFG.DownedMinHealth end
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	lockCharacter(plr, true)
	startDownedGuard(plr)

	-- decide sequence (exclusive)
	local doRefusal = rollRefusal(plr)
	local doPhase3 = (not doRefusal) and rollPhase3(plr)

	local payload = {
		cause = causeTag or "Unknown",

		-- FORCE REFUSAL
		refusal = true,
		phase3 = false,

		mode = "refusal",
		sequence = "refusal",

		showMusicCredit = false,
		empowerDuration = CFG.EmpowerDuration,
	}

	StartDeathSequenceRE:FireClient(plr, payload)


	-- timeout failsafe
	task.delay(CFG.ClientTimeout, function()
		if not plr.Parent then return end
		local st2 = state[plr]
		if not st2 or st2.active ~= true then return end
		if st2.token ~= token then return end
		if not isDowned(plr) then return end

		-- if gameplay stopped (menu), just clear
		if not isGameplayActive(plr) then
			st2.active = false
			setDowned(plr, false)
			setDeathSequenceActive(plr, false)
			stopDownedGuard(plr)
			lockCharacter(plr, false)
			return
		end

		-- revive fallback
		local c = plr.Character
		local h = c and c:FindFirstChildOfClass("Humanoid")
		if h then
			h.Health = math.max(h.MaxHealth * 0.65, 35)
		end

		st2.active = false
		setDowned(plr, false)
		setDeathSequenceActive(plr, false)
		stopDownedGuard(plr)
		lockCharacter(plr, false)
		giveIFrames(plr, CFG.IFramesAfter)
		st2.cooldownUntil = now() + CFG.PostSequenceCooldown
	end)
end

--========================
-- FINISH FROM CLIENT
--========================
FinishDeathSequenceRE.OnServerEvent:Connect(function(plr: Player, payload)
	if not plr or not plr.Parent then return end
	if not isGameplayActive(plr) then return end

	local st = ensureState(plr)
	if not st.active then return end
	if not isDowned(plr) then
		-- if someone else cleared downed, do not trust this finish
		st.active = false
		setDeathSequenceActive(plr, false)
		stopDownedGuard(plr)
		return
	end

	local outcome = (payload and payload.outcome) or "revive"
	local requested = tonumber(payload and payload.postIFrames) or CFG.IFramesAfter
	local postI = math.clamp(requested, 0, CFG.MaxPostIFrames)

	-- clear downed state
	st.active = false
	setDowned(plr, false)
	setDeathSequenceActive(plr, false)
	stopDownedGuard(plr)
	st.cooldownUntil = now() + CFG.PostSequenceCooldown

	-- apply outcome
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")

	if outcome == "empower" then
		if hum then hum.Health = math.max(hum.MaxHealth * 0.75, 50) end
		lockCharacter(plr, false)
		giveIFrames(plr, postI)
		plr:SetAttribute("EmpoweredUntil", now() + CFG.EmpowerDuration)
		return
	end

	-- revive
	if CFG.ReviveUsesLoadCharacter then
		if safeLoadCharacter(plr, "Finish_revive") then
			task.wait(0.05)
			giveIFrames(plr, postI)
		end
	else
		if hum then
			hum.Health = math.max(hum.MaxHealth * 0.65, 35)
		end
		lockCharacter(plr, false)
		giveIFrames(plr, postI)
	end
end)

--========================
-- CHARACTER HOOKING
--========================
local function disconnectHooks(plr: Player)
	local st = ensureState(plr)
	for _, c in ipairs(st.hookConns) do
		if c then c:Disconnect() end
	end
	st.hookConns = {}
end

local function hookCharacter(plr: Player, char: Model)
	disconnectHooks(plr)

	local st = ensureState(plr)

	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end

	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false

	-- Hard local debounce for this humanoid
	local fired = false
	local function tryFire(cause)
		if fired then return end
		-- server-level debounces still apply, this just stops spam
		fired = true
		beginDeathSequence(plr, cause)
		-- allow re-arm after a moment if sequence did not actually start
		task.delay(0.35, function()
			local st2 = state[plr]
			if not st2 or not plr.Parent then return end
			if st2.active or isDowned(plr) then
				-- keep fired true while active
				return
			end
			fired = false
		end)
	end

	table.insert(st.hookConns, hum.HealthChanged:Connect(function(hp)
		if not isGameplayActive(plr) then return end
		if isDowned(plr) then return end
		if hp <= 0 then
			-- keep alive immediately
			if hum.Health <= 0 then hum.Health = CFG.DownedMinHealth end
			tryFire("LethalDamage")
		end
	end))

	table.insert(st.hookConns, hum.Died:Connect(function()
		if not isGameplayActive(plr) then return end
		if isDowned(plr) then return end
		-- keep alive if anything slipped through
		if hum.Health <= 0 then hum.Health = CFG.DownedMinHealth end
		tryFire("HumanoidDied")
	end))
end

local function tryHookIfGameplay(plr: Player)
	if isGameplayActive(plr) and plr.Character then
		hookCharacter(plr, plr.Character)
	end
end

--========================
-- PLAYER LIFECYCLE
--========================
local respawnDebounce = {}

Players.PlayerAdded:Connect(function(plr: Player)
	local st = ensureState(plr)

	-- attributes
	plr:SetAttribute("Downed", false)
	plr:SetAttribute("DeathSequenceActive", false)
	plr:SetAttribute("IFrameUntil", 0)
	plr:SetAttribute("EmpoweredUntil", 0)
	plr:SetAttribute("__DeathSeqToken", 0)

	-- if you want: per-player debug force toggles
	-- plr:SetAttribute("ForceRefusal", false)
	-- plr:SetAttribute("ForcePhase3", false)

	plr.CharacterAdded:Connect(function(char)
		-- clear server state on new character
		st.active = false
		st.cooldownUntil = now() + 0.25
		setDowned(plr, false)
		setDeathSequenceActive(plr, false)
		stopDownedGuard(plr)
		disconnectHooks(plr)

		if isGameplayActive(plr) then
			hookCharacter(plr, char)
		end
	end)

	-- if gameplay becomes active later, hook existing character
	plr:GetAttributeChangedSignal("GameStarted"):Connect(function()
		tryHookIfGameplay(plr)
	end)
	plr:GetAttributeChangedSignal("InMenu"):Connect(function()
		tryHookIfGameplay(plr)
	end)
end)

Players.PlayerRemoving:Connect(function(plr: Player)
	local st = state[plr]
	if st then
		disconnectHooks(plr)
		if st.downedGuardConn then st.downedGuardConn:Disconnect() end
	end
	respawnDebounce[plr] = nil
	state[plr] = nil
end)

--========================
-- OPTIONAL: MANUAL RESPAWN REQUEST
--========================
if RequestRespawnRE then
	RequestRespawnRE.OnServerEvent:Connect(function(plr: Player, sourceTag)
		if not plr or not plr.Parent then return end
		if respawnDebounce[plr] then return end
		respawnDebounce[plr] = true

		if not isGameplayActive(plr) then
			task.delay(0.25, function() respawnDebounce[plr] = nil end)
			return
		end

		if plr:GetAttribute("DeathSequenceActive") or plr:GetAttribute("Downed") then
			task.delay(0.25, function() respawnDebounce[plr] = nil end)
			return
		end

		-- if you truly want LoadCharacter here, do it safely
		safeLoadCharacter(plr, "RequestRespawnRE_" .. tostring(sourceTag))

		task.delay(CFG.RespawnDebounce, function()
			respawnDebounce[plr] = nil
		end)
	end)
end

-- Export helpers (optional)
_G.TriggerFakeDeath = function(plr, causeTag)
	beginDeathSequence(plr, tostring(causeTag or "ManualTrigger"))
end
_G.PlayerHasIFrames = isIFramed
