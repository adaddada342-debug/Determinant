-- ServerScriptService/DeterminantCombat/CombatService.server.lua
-- Owns: health, stamina, dodge permissions, invulnerability windows, damage rules.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Constants = require(ReplicatedStorage:WaitForChild("DeterminantCombat"):WaitForChild("Modules"):WaitForChild("CombatConstants"))

local root = ReplicatedStorage:FindFirstChild("DeterminantCombat")
if not root then
	root = Instance.new("Folder")
	root.Name = "DeterminantCombat"
	root.Parent = ReplicatedStorage
end

local remotes = root:FindFirstChild("Remotes")
if not remotes then
	remotes = Instance.new("Folder")
	remotes.Name = "Remotes"
	remotes.Parent = root
end

local function ensureRE(name)
	local re = remotes:FindFirstChild(name)
	if not re then
		re = Instance.new("RemoteEvent")
		re.Name = name
		re.Parent = remotes
	end
	return re
end

local CombatRE = ensureRE("CombatRE")
local DodgeRE = ensureRE("DodgeRE")
ensureRE("BulletHellRE") -- created here so clients can WaitForChild it

local CombatService = {}
_G.DeterminantCombatService = CombatService -- easy access if you like

local function now()
	return os.clock()
end

local function getHumanoid(plr)
	local ch = plr.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

local function clamp(x, a, b)
	if x < a then return a end
	if x > b then return b end
	return x
end

function CombatService.InitPlayer(plr)
	plr:SetAttribute("MaxHealth", Constants.MAX_HEALTH)
	plr:SetAttribute("Health", Constants.MAX_HEALTH)

	plr:SetAttribute("MaxStamina", Constants.MAX_STAMINA)
	plr:SetAttribute("Stamina", Constants.MAX_STAMINA)

	plr:SetAttribute("InvulnUntil", 0)
	plr:SetAttribute("DamageImmuneUntil", 0)
	plr:SetAttribute("DodgeCooldownUntil", 0)

	local hum = getHumanoid(plr)
	if hum then
		hum.MaxHealth = Constants.MAX_HEALTH
		hum.Health = Constants.MAX_HEALTH
		hum.BreakJointsOnDeath = false
	end
end

function CombatService.CanTakeDamage(plr)
	local t = now()
	local inv = plr:GetAttribute("InvulnUntil") or 0
	local imm = plr:GetAttribute("DamageImmuneUntil") or 0
	return (t >= inv) and (t >= imm)
end

function CombatService.ApplyDamage(plr, amount, sourceTag)
	amount = tonumber(amount) or 0
	if amount <= 0 then return false end
	if not CombatService.CanTakeDamage(plr) then return false end

	local hp = plr:GetAttribute("Health") or Constants.MAX_HEALTH
	hp = clamp(hp - amount, 0, plr:GetAttribute("MaxHealth") or Constants.MAX_HEALTH)
	plr:SetAttribute("Health", hp)

	-- Brief post-hit immunity prevents “bullet blender” deaths
	plr:SetAttribute("DamageImmuneUntil", now() + Constants.POST_HIT_IMMUNITY)

	local hum = getHumanoid(plr)
	if hum then
		-- Keep humanoid in sync so death works naturally
		hum.Health = hp
	end

	CombatRE:FireClient(plr, "HitFeedback", {
		source = sourceTag or "unknown",
		newHealth = hp,
	})

	return true
end

local function regenLoopStep(dt)
	for _, plr in ipairs(Players:GetPlayers()) do
		local maxStam = plr:GetAttribute("MaxStamina") or Constants.MAX_STAMINA
		local stam = plr:GetAttribute("Stamina") or maxStam
		if stam < maxStam then
			stam = clamp(stam + Constants.STAMINA_REGEN_PER_SEC * dt, 0, maxStam)
			plr:SetAttribute("Stamina", stam)
		end
	end
end

-- Dodge handling: server validates stamina & cooldown
DodgeRE.OnServerEvent:Connect(function(plr, payload)
	payload = payload or {}
	local dir = payload.dir
	if typeof(dir) ~= "Vector3" then
		CombatRE:FireClient(plr, "DodgeAck", { ok = false, reason = "bad_dir" })
		return
	end

	local t = now()
	local cdUntil = plr:GetAttribute("DodgeCooldownUntil") or 0
	if t < cdUntil then
		CombatRE:FireClient(plr, "DodgeAck", { ok = false, reason = "cooldown" })
		return
	end

	local stam = plr:GetAttribute("Stamina") or Constants.MAX_STAMINA
	if stam < Constants.DODGE_COST then
		CombatRE:FireClient(plr, "DodgeAck", { ok = false, reason = "no_stamina" })
		return
	end

	-- Approve
	plr:SetAttribute("Stamina", stam - Constants.DODGE_COST)
	plr:SetAttribute("InvulnUntil", t + Constants.DODGE_IFRAMES)
	plr:SetAttribute("DodgeCooldownUntil", t + Constants.DODGE_COOLDOWN)

	CombatRE:FireClient(plr, "DodgeAck", {
		ok = true,
		duration = Constants.DODGE_DURATION,
		impulse = Constants.DODGE_IMPULSE,
	})
end)

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function()
		task.defer(function()
			CombatService.InitPlayer(plr)
		end)
	end)
end)

-- Init already connected players (studio play solo edge)
for _, plr in ipairs(Players:GetPlayers()) do
	CombatService.InitPlayer(plr)
end

RunService.Heartbeat:Connect(regenLoopStep)

print("[DeterminantCombat] CombatService loaded")
