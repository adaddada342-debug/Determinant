-- AsrielSystem.server.lua
-- Server authority:
-- - Only whitelisted UserIds can activate Asriel mode (secret phrase)
-- - Mode persists until Final ability is used (then it ends)
-- - Cooldowns + phase state + gameplay damage are server-owned
-- - VFX/UI are client-rendered but globally visible via broadcast
-- - Global overhead typed chat for ALL players (typewriter bubble)
--
-- AMENDED:
-- ✅ Passive "Reality Pressure" aura while active (phase-scaled)
-- ✅ Damage falloff + optional knockback pulse for big moves
-- ✅ Safer remote payload validation + token whitelist
-- ✅ Better origin validation + target filtering via radius checks

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

-- ========= Remotes =========
local Remotes = ReplicatedStorage:FindFirstChild("Remotes") or Instance.new("Folder")
Remotes.Name = "Remotes"
Remotes.Parent = ReplicatedStorage

local AsrielEvent = Remotes:FindFirstChild("AsrielEvent") or Instance.new("RemoteEvent")
AsrielEvent.Name = "AsrielEvent"
AsrielEvent.Parent = Remotes

-- ========= Config =========
local CFG = {
	Allowed = {
		[2411879980] = true, -- <-- your UserId(s)
	},

	TriggerPhrase = "Chara? Are you there? It's me..",
	PurgeLine = "It's time to purge this timeline.",
	FinalLine = "Just let me win!",

	Abilities = {
		StarBlazing = "STAR_BLAZING",
		ShockerBreaker = "SHOCKER_BREAKER",
		ChaosSabers = "CHAOS_SABERS",
		Purge = "PURGE",
		Final = "FINAL",
	},

	Cooldowns = {
		STAR_BLAZING = 8,
		SHOCKER_BREAKER = 10,
		CHAOS_SABERS = 7,
		PURGE = 25,
		FINAL = 40,
	},

	Damage = {
		STAR_BLAZING = 18,
		SHOCKER_BREAKER = 22,
		CHAOS_SABERS = 28,
		FINAL = 60,
	},

	Range = {
		STAR_BLAZING = 55,
		SHOCKER_BREAKER = 45,
		CHAOS_SABERS = 20,
		FINAL = 120,
	},

	FinalLockSeconds = 6.5,

	-- ✅ Passive "presence" pressure while AsrielActive (per second tick)
	Presence = {
		Enabled = true,
		Radius = 42,
		Tick = 0.25, -- seconds
		BaseDPS_Phase1 = 2.5,
		BaseDPS_Phase2 = 5.5,
		SlowPct_Phase1 = 0.08, -- subtle
		SlowPct_Phase2 = 0.18, -- noticeable
		MinDistanceNoPressure = 8, -- don't punish hugging too hard / jitter
	},

	-- ✅ Knockback tuning for the “big” stuff (server-side impulse)
	Knockback = {
		Enabled = true,
		STAR_BLAZING = 40,
		SHOCKER_BREAKER = 55,
		CHAOS_SABERS = 25,
		FINAL = 95,
		Upward = 18,
	},
}

-- ========= State =========
type AsrielState = {
	active: boolean,
	phase: number,
	cooldowns: {[string]: number},
	finalFired: boolean,
	presenceAcc: number,
}

local stateByUserId: {[number]: AsrielState} = {}

local function isAllowed(plr: Player): boolean
	return CFG.Allowed[plr.UserId] == true
end

local function getState(plr: Player): AsrielState
	local s = stateByUserId[plr.UserId]
	if not s then
		s = { active = false, phase = 1, cooldowns = {}, finalFired = false, presenceAcc = 0 }
		stateByUserId[plr.UserId] = s
	end
	return s
end

local function now(): number
	return os.clock()
end

local function broadcast(kind: string, payload: any?)
	payload = payload or {}
	payload.t0 = payload.t0 or Workspace:GetServerTimeNow()
	payload.seed = payload.seed or math.random(1, 2^31 - 1)
	AsrielEvent:FireAllClients(kind, payload)
end

local function getHRP(plr: Player): BasePart?
	local char = plr.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function getHum(plr: Player): Humanoid?
	local char = plr.Character
	if not char then return nil end
	return char:FindFirstChildOfClass("Humanoid") :: Humanoid?
end

local function setWalkSlow(plr: Player, slowPct: number)
	local hum = getHum(plr)
	if not hum then return end
	local base = hum:GetAttribute("__BaseWalkSpeed")
	if not base then
		hum:SetAttribute("__BaseWalkSpeed", hum.WalkSpeed)
		base = hum.WalkSpeed
	end
	hum.WalkSpeed = math.max(6, base * (1 - slowPct))
end

local function clearWalkSlow(plr: Player)
	local hum = getHum(plr)
	if not hum then return end
	local base = hum:GetAttribute("__BaseWalkSpeed")
	if base then
		hum.WalkSpeed = base
		hum:SetAttribute("__BaseWalkSpeed", nil)
	end
end

local function setAsrielActive(plr: Player, active: boolean)
	local s = getState(plr)
	s.active = active
	s.finalFired = false
	s.phase = 1
	s.cooldowns = {}
	s.presenceAcc = 0

	plr:SetAttribute("AsrielActive", active)
	plr:SetAttribute("AsrielPhase", s.phase)

	-- Clean slow if turning off
	if not active then
		for _, p in ipairs(Players:GetPlayers()) do
			clearWalkSlow(p)
		end
	end

	if active then
		broadcast("AsrielStart", {
			ownerUserId = plr.UserId,
			ownerName = plr.Name,
		})
	else
		broadcast("AsrielEnd", {
			ownerUserId = plr.UserId,
			ownerName = plr.Name,
		})
	end
end

local function setPhase(plr: Player, phase: number)
	local s = getState(plr)
	if not s.active then return end
	s.phase = phase
	plr:SetAttribute("AsrielPhase", phase)
	broadcast("AsrielPhase", {
		ownerUserId = plr.UserId,
		ownerName = plr.Name,
		phase = phase,
	})
end

local function canUse(plr: Player, abilityToken: string): (boolean, number)
	local s = getState(plr)
	if not s.active then return false, 0 end
	if s.finalFired then return false, 0 end

	local cd = CFG.Cooldowns[abilityToken]
	if not cd then
		return false, 0 -- unknown token
	end

	local tStamp = s.cooldowns[abilityToken] or 0
	local remaining = (tStamp + cd) - now()
	if remaining > 0 then
		return false, remaining
	end
	return true, 0
end

local function stampCooldown(plr: Player, abilityToken: string)
	local s = getState(plr)
	s.cooldowns[abilityToken] = now()
end

local function knockbackFrom(origin: Vector3, targetHRP: BasePart, strength: number)
	if not CFG.Knockback.Enabled then return end
	local dir = (targetHRP.Position - origin)
	local mag = dir.Magnitude
	if mag < 0.001 then
		dir = Vector3.new(0, 0, 1)
	else
		dir = dir.Unit
	end

	-- Use AssemblyLinearVelocity for modern Roblox physics
	local vel = dir * strength + Vector3.new(0, CFG.Knockback.Upward, 0)
	targetHRP.AssemblyLinearVelocity = targetHRP.AssemblyLinearVelocity + vel
end

local function damageInRadius(origin: Vector3, radius: number, amount: number, excludeUserId: number, knockStrength: number?)
	-- Simple falloff makes it feel less “flat”
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId ~= excludeUserId then
			local hrp = getHRP(p)
			local hum = getHum(p)
			if hrp and hum and hum.Health > 0 then
				local dist = (hrp.Position - origin).Magnitude
				if dist <= radius then
					local t = math.clamp(dist / math.max(1, radius), 0, 1)
					local dealt = math.max(1, math.floor(amount * (1 - 0.55 * t)))
					hum:TakeDamage(dealt)

					if knockStrength and knockStrength > 0 then
						knockbackFrom(origin, hrp, math.max(10, knockStrength * (1 - 0.6 * t)))
					end

					-- client hit-confirm (screen shake, flash, etc)
					broadcast("HitConfirm", {
						targetUserId = p.UserId,
						origin = origin,
						intensity = math.clamp(dealt / 30, 0.12, 1.0),
					})
				end
			end
		end
	end
end

-- ========= Ability handlers =========
local function doStarBlazing(plr: Player)
	local hrp = getHRP(plr); if not hrp then return end
	stampCooldown(plr, CFG.Abilities.StarBlazing)

	broadcast("VFX", {
		ability = CFG.Abilities.StarBlazing,
		ownerUserId = plr.UserId,
		origin = hrp.Position,
		phase = plr:GetAttribute("AsrielPhase") or 1,
	})

	damageInRadius(hrp.Position, CFG.Range.STAR_BLAZING, CFG.Damage.STAR_BLAZING, plr.UserId, CFG.Knockback.STAR_BLAZING)
end

local function doShockerBreaker(plr: Player)
	local hrp = getHRP(plr); if not hrp then return end
	stampCooldown(plr, CFG.Abilities.ShockerBreaker)

	broadcast("VFX", {
		ability = CFG.Abilities.ShockerBreaker,
		ownerUserId = plr.UserId,
		origin = hrp.Position,
		phase = plr:GetAttribute("AsrielPhase") or 1,
	})

	damageInRadius(hrp.Position, CFG.Range.SHOCKER_BREAKER, CFG.Damage.SHOCKER_BREAKER, plr.UserId, CFG.Knockback.SHOCKER_BREAKER)
end

local function doChaosSabers(plr: Player)
	local hrp = getHRP(plr); if not hrp then return end
	stampCooldown(plr, CFG.Abilities.ChaosSabers)

	broadcast("VFX", {
		ability = CFG.Abilities.ChaosSabers,
		ownerUserId = plr.UserId,
		origin = hrp.Position,
		phase = plr:GetAttribute("AsrielPhase") or 1,
	})

	damageInRadius(hrp.Position, CFG.Range.CHAOS_SABERS, CFG.Damage.CHAOS_SABERS, plr.UserId, CFG.Knockback.CHAOS_SABERS)
end

local function doPurge(plr: Player)
	local hrp = getHRP(plr); if not hrp then return end
	stampCooldown(plr, CFG.Abilities.Purge)

	setPhase(plr, 2)

	broadcast("OverheadTyped", {
		ownerUserId = plr.UserId,
		text = CFG.PurgeLine,
		style = "asriel",
	})

	broadcast("VFX", {
		ability = CFG.Abilities.Purge,
		ownerUserId = plr.UserId,
		origin = hrp.Position,
		phase = 2,
	})

	-- Punch nearby players a bit on phase shift (feels like gravity changed)
	damageInRadius(hrp.Position, 30, 10, plr.UserId, 35)
end

local function doFinal(plr: Player)
	local hrp = getHRP(plr); if not hrp then return end
	local s = getState(plr)
	s.finalFired = true
	stampCooldown(plr, CFG.Abilities.Final)

	broadcast("OverheadTyped", {
		ownerUserId = plr.UserId,
		text = CFG.FinalLine,
		style = "asriel",
	})

	broadcast("VFX", {
		ability = CFG.Abilities.Final,
		ownerUserId = plr.UserId,
		origin = hrp.Position,
		phase = plr:GetAttribute("AsrielPhase") or 2,
	})

	damageInRadius(hrp.Position, CFG.Range.FINAL, CFG.Damage.FINAL, plr.UserId, CFG.Knockback.FINAL)

	task.delay(CFG.FinalLockSeconds, function()
		if plr.Parent then
			setAsrielActive(plr, false)
		end
	end)
end

local function handleAbility(plr: Player, token: string)
	local ok = canUse(plr, token)
	if not ok then return end

	if token == CFG.Abilities.StarBlazing then
		doStarBlazing(plr)
	elseif token == CFG.Abilities.ShockerBreaker then
		doShockerBreaker(plr)
	elseif token == CFG.Abilities.ChaosSabers then
		doChaosSabers(plr)
	elseif token == CFG.Abilities.Purge then
		doPurge(plr)
	elseif token == CFG.Abilities.Final then
		doFinal(plr)
	end
end

-- ========= Passive Presence Loop =========
RunService.Heartbeat:Connect(function(dt)
	if not CFG.Presence.Enabled then return end

	for _, plr in ipairs(Players:GetPlayers()) do
		local s = stateByUserId[plr.UserId]
		if s and s.active and not s.finalFired then
			local hrp = getHRP(plr)
			if hrp then
				s.presenceAcc += dt
				if s.presenceAcc >= CFG.Presence.Tick then
					s.presenceAcc = 0

					local phase = plr:GetAttribute("AsrielPhase") or s.phase or 1
					local dps = (phase == 2) and CFG.Presence.BaseDPS_Phase2 or CFG.Presence.BaseDPS_Phase1
					local slow = (phase == 2) and CFG.Presence.SlowPct_Phase2 or CFG.Presence.SlowPct_Phase1

					local tickDmg = dps * CFG.Presence.Tick

					for _, p in ipairs(Players:GetPlayers()) do
						if p.UserId ~= plr.UserId then
							local thrp = getHRP(p)
							local hum = getHum(p)
							if thrp and hum and hum.Health > 0 then
								local dist = (thrp.Position - hrp.Position).Magnitude
								if dist <= CFG.Presence.Radius and dist >= CFG.Presence.MinDistanceNoPressure then
									hum:TakeDamage(tickDmg)
									setWalkSlow(p, slow)

									broadcast("PresenceTick", {
										ownerUserId = plr.UserId,
										targetUserId = p.UserId,
										origin = hrp.Position,
										phase = phase,
										intensity = math.clamp(1 - (dist / CFG.Presence.Radius), 0.05, 1),
									})
								else
									-- clear slow when out of range
									clearWalkSlow(p)
								end
							end
						end
					end
				end
			end
		end
	end
end)

-- ========= Remote: client requests =========
AsrielEvent.OnServerEvent:Connect(function(plr, kind, payload)
	if kind == "Ability" then
		if not isAllowed(plr) then return end
		local token = payload and payload.token
		if typeof(token) ~= "string" then return end

		-- Token whitelist
		if CFG.Cooldowns[token] == nil then
			return
		end

		handleAbility(plr, token)
	end
end)

-- ========= Global overhead typed chat for ALL players =========
local function onPlayerChat(plr: Player, msg: string)
	broadcast("OverheadTyped", {
		ownerUserId = plr.UserId,
		text = msg,
		style = "default",
	})

	if isAllowed(plr) and msg == CFG.TriggerPhrase then
		local s = getState(plr)
		if not s.active then
			setAsrielActive(plr, true)
		end
	end
end

Players.PlayerAdded:Connect(function(plr)
	plr.Chatted:Connect(function(msg)
		onPlayerChat(plr, msg)
	end)

	plr.CharacterAdded:Connect(function()
		local s = getState(plr)
		if s.active then
			broadcast("AsrielStart", { ownerUserId = plr.UserId, ownerName = plr.Name })
			broadcast("AsrielPhase", { ownerUserId = plr.UserId, ownerName = plr.Name, phase = s.phase })
		end
	end)
end)

Players.PlayerRemoving:Connect(function(plr)
	stateByUserId[plr.UserId] = nil
end)

print("[AsrielSystem] Loaded. Remember to set Allowed UserIds and TriggerPhrase.")
