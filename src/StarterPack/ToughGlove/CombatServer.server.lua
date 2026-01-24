-- ServerScriptService/CombatServer.server.lua
-- Authoritative weapon damage router:
-- ✅ Phase2 = battle damage via _G.BattleService.DealPhase2BattleDamage
-- ✅ Overworld = optional humanoid damage if provided
-- ✅ Auto-binds any Tool.RemoteEvent named "CombatRE"
-- ✅ Handles payload "M1" or { damage = number, humanoid = Humanoid }

local Players = game:GetService("Players")

local BASE_DAMAGE = 12
local DEBUG = true

-- anti-spam per player (server-side)
local MIN_INTERVAL = 0.10
local lastHitAt = {} :: {[Player]: number}

local function dprint(...)
	if DEBUG then
		print("[CombatServer]", ...)
	end
end

local function isPhase2(plr: Player)
	return tostring(plr:GetAttribute("__BattlePhase") or "None") == "Phase2"
end

local function canHit(plr: Player)
	local now = os.clock()
	local last = lastHitAt[plr] or 0
	if (now - last) < MIN_INTERVAL then return false end
	lastHitAt[plr] = now
	return true
end

local function battleDeal(plr: Player, dmg: number)
	if _G.BattleService and _G.BattleService.DealPhase2BattleDamage then
		_G.BattleService.DealPhase2BattleDamage(plr, dmg)
		return true
	end
	return false
end

local function bindCombatRE(re: RemoteEvent)
	if re:GetAttribute("__BoundCombatServer") then return end
	re:SetAttribute("__BoundCombatServer", true)

	dprint("Bound:", re:GetFullName())

	re.OnServerEvent:Connect(function(plr: Player, payload)
		if not plr or not plr.Parent then return end
		if not canHit(plr) then return end

		local dmg = BASE_DAMAGE
		local humanoidTarget: Humanoid? = nil

		if typeof(payload) == "table" then
			if payload.damage ~= nil then
				dmg = tonumber(payload.damage) or dmg
			end
			local h = payload.humanoid
			if typeof(h) == "Instance" and h:IsA("Humanoid") then
				humanoidTarget = h
			end
		end

		dmg = math.clamp(math.floor(dmg), 1, 250)

		local phase = tostring(plr:GetAttribute("__BattlePhase") or "None")
		dprint("Event from", plr.Name, "payload=", typeof(payload), payload, "phase=", phase, "dmg=", dmg)

		-- ✅ Phase2 battle damage (authoritative)
		if phase == "Phase2" then
			local ok = battleDeal(plr, dmg)
			if not ok then
				warn("[CombatServer] BattleService.DealPhase2BattleDamage missing")
			end
			return
		end

		-- ✅ Overworld fallback (only works if you pass a humanoid)
		if humanoidTarget and humanoidTarget.Health > 0 then
			humanoidTarget:TakeDamage(dmg)
			return
		end
	end)
end

local function scan(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("RemoteEvent") and d.Name == "CombatRE" then
			bindCombatRE(d)
		end
	end
end

local function hook(root: Instance)
	root.DescendantAdded:Connect(function(d)
		if d:IsA("RemoteEvent") and d.Name == "CombatRE" then
			task.defer(function()
				bindCombatRE(d)
			end)
		end
	end)
end

Players.PlayerAdded:Connect(function(plr)
	lastHitAt[plr] = 0

	local function onChar(char: Model)
		task.defer(function()
			scan(char)
			hook(char)
		end)
	end

	-- Backpack tools
	task.defer(function()
		if plr:FindFirstChild("Backpack") then
			scan(plr.Backpack)
			hook(plr.Backpack)
		end
	end)

	plr.CharacterAdded:Connect(onChar)
	if plr.Character then onChar(plr.Character) end
end)

Players.PlayerRemoving:Connect(function(plr)
	lastHitAt[plr] = nil
end)

dprint("Loaded (Phase2 routes to BattleService).")
