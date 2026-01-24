-- ServerScriptService/Systems/AwakeningService.lua
-- Violence vs Mercy progression + Awakening system.
-- Kills => more power, more backlash. Spares => stability, fewer debuffs, lower damage growth.
-- Debug: press J (Studio only) to force Awakening.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Systems = script.Parent
local MemoryService = require(Systems:WaitForChild("MemoryService"))
local StatusService = require(Systems:WaitForChild("StatusService"))

local AwakeningService = {}

local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
remotesFolder.Name = "Remotes"
remotesFolder.Parent = ReplicatedStorage

local AwakeningEvent: RemoteEvent = remotesFolder:FindFirstChild("AwakeningEvent") or Instance.new("RemoteEvent")
AwakeningEvent.Name = "AwakeningEvent"
AwakeningEvent.Parent = remotesFolder

-- runtime only (timers / loops)
local state: {[Player]: {runId: number, endsAt: number}} = {}
local saveCounter: {[number]: number} = {} -- [userId] = actions since last save

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

local function ensureTraits(mem)
	mem.traits = mem.traits or {}
	mem.traits.awakening = mem.traits.awakening or {}

	local a = mem.traits.awakening
	a.corruption = tonumber(a.corruption) or 0
	a.stability  = tonumber(a.stability) or 0
	a.charge     = tonumber(a.charge) or 0
	a.count      = tonumber(a.count) or 0

	mem.traits.violence = tonumber(mem.traits.violence) or 0
	mem.traits.mercy    = tonumber(mem.traits.mercy) or 0

	a.corruption = math.clamp(a.corruption, 0, 100)
	a.stability  = math.clamp(a.stability, 0, 100)
	a.charge     = math.clamp(a.charge, 0, 150)
end

local function applyToAttributes(plr: Player, mem)
	ensureTraits(mem)
	local a = mem.traits.awakening

	plr:SetAttribute("SoulViolence", mem.traits.violence)
	plr:SetAttribute("SoulMercy", mem.traits.mercy)
	plr:SetAttribute("SoulCorruption", a.corruption)
	plr:SetAttribute("SoulStability", a.stability)
	plr:SetAttribute("SoulCharge", a.charge)
end

local function markDirtyMaybeSave(plr: Player, force: boolean?)
	MemoryService:MarkDirty(plr)

	local uid = plr.UserId
	saveCounter[uid] = (saveCounter[uid] or 0) + 1

	-- Save occasionally (not every hit), and always when forced.
	if force or (saveCounter[uid] >= 12) then
		saveCounter[uid] = 0
		task.defer(function()
			pcall(function()
				MemoryService:Save(plr)
			end)
		end)
	end
end

function AwakeningService:GetMemory(plr: Player)
	local mem = MemoryService:Get(plr)
	if not mem then return nil end
	ensureTraits(mem)
	return mem
end

function AwakeningService:IsAwakened(plr: Player): boolean
	return plr:GetAttribute("SoulIsAwakened") == true
end

function AwakeningService:GetBaseDamageMultiplier(plr: Player): number
	local mem = self:GetMemory(plr)
	if not mem then return 1 end

	local net = (mem.traits.violence or 0) - (mem.traits.mercy or 0)
	-- each net kill = +1% dmg; net mercy = -1% dmg (clamped)
	return math.clamp(1 + (net * 0.01), 0.7, 1.6)
end

function AwakeningService:GetOutgoingDamageMultiplier(plr: Player, _context: string?): number
	local base = self:GetBaseDamageMultiplier(plr)
	if not self:IsAwakened(plr) then
		return base
	end

	local corruption = tonumber(plr:GetAttribute("SoulCorruption")) or 0
	local stability  = tonumber(plr:GetAttribute("SoulStability")) or 0

	-- Awakening bonus: more Corruption = more power, more Stability = less “rage spike”.
	local bonus = math.clamp(1.20 + (corruption * 0.012) - (stability * 0.006), 1.05, 2.35)
	return base * bonus
end

local function computeAutoChance(corruption: number, stability: number): number
	local c = clamp01(corruption / 100)
	local s = clamp01(stability / 100)
	return math.clamp(0.12 + (c * 0.55) - (s * 0.30), 0.05, 0.70)
end

local function themeFromStats(corruption: number, stability: number)
	if stability >= corruption + 10 then return "CALM" end
	if corruption >= stability + 10 then return "RAGE" end
	return "DUAL"
end

function AwakeningService:StartAwakening(plr: Player, reason: string?)
	if not plr or not plr.Parent then return end
	if self:IsAwakened(plr) then return end

	local mem = self:GetMemory(plr)
	if not mem then return end
	local a = mem.traits.awakening

	local corruption = a.corruption
	local stability  = a.stability
	local theme = themeFromStats(corruption, stability)

	local duration  = math.clamp(18 + math.floor(corruption / 12) - math.floor(stability / 20), 14, 30)
	local intensity = math.clamp(0.35 + (corruption / 150), 0.35, 1.0)

	-- spend charge + count
	a.charge = math.clamp(a.charge - 100, 0, 150)
	a.count = (a.count or 0) + 1
	markDirtyMaybeSave(plr, true)
	applyToAttributes(plr, mem)

	plr:SetAttribute("SoulIsAwakened", true)
	plr:SetAttribute("SoulAwakenEndsAt", os.clock() + duration)
	plr:SetAttribute("SoulAwakenIntensity", intensity)
	plr:SetAttribute("SoulAwakenTheme", theme)

	AwakeningEvent:FireClient(plr, "Begin", {
		reason = tostring(reason or "Auto"),
		duration = duration,
		intensity = intensity,
		theme = theme,
		corruption = corruption,
		stability = stability,
	})

	local runId = (state[plr] and state[plr].runId or 0) + 1
	state[plr] = { runId = runId, endsAt = os.clock() + duration }

	task.spawn(function()
		local lastPulse = 0
		local lastBacklash = 0

		while plr.Parent and self:IsAwakened(plr) do
			local s = state[plr]
			if not s or s.runId ~= runId then return end

			local t = os.clock()
			if t >= s.endsAt then
				break
			end

			-- client visual pulse
			if t - lastPulse >= 2.2 then
				lastPulse = t
				AwakeningEvent:FireClient(plr, "Pulse", { intensity = intensity, theme = theme })
			end

			-- server backlash
			if t - lastBacklash >= 2.8 then
				lastBacklash = t

				local char = plr.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local delta = (corruption - stability) / 100
					local badness = math.clamp(delta, 0, 1)

					local slowMult = math.clamp(0.95 - (badness * 0.30), 0.60, 0.95)
					local slowDur  = 0.55 + (badness * 0.65)
					StatusService:Apply(hum, "Slow", slowDur, { mult = slowMult })

					if badness >= 0.55 and math.random() < (0.10 + badness * 0.18) then
						StatusService:Apply(hum, "Stun", 0.22 + badness * 0.18)
					end

					if badness >= 0.70 then
						hum:TakeDamage(1 + math.floor(3 * badness))
					end
				end
			end

			task.wait(0.15)
		end

		if state[plr] and state[plr].runId == runId then
			state[plr] = nil
		end

		plr:SetAttribute("SoulIsAwakened", false)
		plr:SetAttribute("SoulAwakenEndsAt", 0)

		AwakeningEvent:FireClient(plr, "End", { reason = tostring(reason or "Timer") })
	end)
end

function AwakeningService:TryAutoAwaken(plr: Player, reason: string)
	if self:IsAwakened(plr) then return end

	local mem = self:GetMemory(plr)
	if not mem then return end
	local a = mem.traits.awakening

	if a.charge < 100 then return end

	local chance = computeAutoChance(a.corruption, a.stability)
	if math.random() <= chance then
		self:StartAwakening(plr, "Auto:" .. tostring(reason))
	else
		-- reduce charge a bit so rolls aren't constant
		a.charge = math.clamp(a.charge - 18, 0, 150)
		markDirtyMaybeSave(plr, false)
		applyToAttributes(plr, mem)
	end
end

function AwakeningService:RecordKill(plr: Player, _info: table?)
	local mem = self:GetMemory(plr)
	if not mem then return end
	local a = mem.traits.awakening

	mem.traits.violence += 1
	a.corruption = math.clamp(a.corruption + 10, 0, 100)
	a.stability  = math.clamp(a.stability - 6, 0, 100)
	a.charge     = math.clamp(a.charge + 28, 0, 150)

	markDirtyMaybeSave(plr, false)
	applyToAttributes(plr, mem)

	-- recoil slow if you're leaning violent
	local char = plr.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 and (a.corruption > a.stability + 10) then
		StatusService:Apply(hum, "Slow", 0.35, { mult = 0.85 })
	end

	self:TryAutoAwaken(plr, "Kill")
end

function AwakeningService:RecordSpare(plr: Player, _info: table?)
	local mem = self:GetMemory(plr)
	if not mem then return end
	local a = mem.traits.awakening

	mem.traits.mercy += 1
	a.stability  = math.clamp(a.stability + 12, 0, 100)
	a.corruption = math.clamp(a.corruption - 4, 0, 100)
	a.charge     = math.clamp(a.charge + 12, 0, 150)

	markDirtyMaybeSave(plr, false)
	applyToAttributes(plr, mem)

	self:TryAutoAwaken(plr, "Spare")
end

function AwakeningService:BindRemotes()
	AwakeningEvent.OnServerEvent:Connect(function(plr, kind, _payload)
		if kind == "DebugAwaken" then
			if not RunService:IsStudio() then return end
			self:StartAwakening(plr, "DebugKeyJ")
		end
	end)
end

function AwakeningService:Init()
	Players.PlayerAdded:Connect(function(plr)
		task.defer(function()
			local mem = self:GetMemory(plr)
			if mem then
				applyToAttributes(plr, mem)
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(plr)
		state[plr] = nil
		saveCounter[plr.UserId] = nil
	end)

	self:BindRemotes()
end

return AwakeningService
