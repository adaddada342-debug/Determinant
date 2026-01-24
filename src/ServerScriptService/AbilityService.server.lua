-- ServerScriptService/AbilityService (NORMAL Script)
-- ✅ AMENDED: GroundSlam damages battle enemy reliably (no overlap query needed)
-- ✅ Still supports overworld enemies via CollectionService tag
-- ✅ Does NOT change battle difficulty/logic: respects Phase2 gate

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local StatusService = require(script.Parent.Systems.StatusService)

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local AbilityRequest  = remotes:WaitForChild("AbilityRequest")
local AbilityImpact   = remotes:WaitForChild("AbilityImpact")
local AbilityFX       = remotes:WaitForChild("AbilityFX")
local AbilityCooldown = remotes:WaitForChild("AbilityCooldown")

local CONFIG = {
	COOLDOWN = 6.0,
	MIN_IMPACT_DELAY = 0.60,
	MAX_IMPACT_DELAY = 6.0,

	RADIUS = 18,
	DAMAGE = 25,

	KNOCKBACK = 70,
	UPWARD = 35,

	-- Enemy rules:
	USE_COLLECTION_TAG = true,
	REQUIRE_ISENEMY_ATTRIBUTE = false,
	DONT_HIT_PLAYERS = true,

	-- Status effects
	STUN_DURATION = 0.35,
}

local ENEMY_TAG = "Enemy"
local castState = {} -- [player] = { lastCast, castStart }

local function now() return os.clock() end

local function getCharHumRoot(player: Player)
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hum or not hrp then return nil end
	return char, hum, hrp
end

local function groundPosFrom(hrp: BasePart)
	local origin = hrp.Position + Vector3.new(0, 2, 0)
	local dir = Vector3.new(0, -120, 0)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { hrp.Parent }
	params.IgnoreWater = true

	local res = workspace:Raycast(origin, dir, params)
	if res then return res.Position end
	return hrp.Position - Vector3.new(0, 3, 0)
end

local function isPlayerCharacter(model: Model)
	return Players:GetPlayerFromCharacter(model) ~= nil
end

local function isEnemyModel(model: Model): boolean
	if CONFIG.USE_COLLECTION_TAG and CollectionService:HasTag(model, ENEMY_TAG) then
		return true
	end
	if CONFIG.REQUIRE_ISENEMY_ATTRIBUTE and model:GetAttribute("IsEnemy") == true then
		return true
	end
	return false
end

local function findTargets(center: Vector3, radius: number, ignoreChar: Model)
	local params = OverlapParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignoreChar }

	local parts = workspace:GetPartBoundsInRadius(center, radius, params)

	local seen = {}
	local targets = {}

	for _, part in ipairs(parts) do
		local model = part:FindFirstAncestorOfClass("Model")
		if model and not seen[model] then
			seen[model] = true

			local hum = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then
				if CONFIG.DONT_HIT_PLAYERS and isPlayerCharacter(model) then
					continue
				end
				if isEnemyModel(model) then
					table.insert(targets, { hum = hum, root = root, model = model })
				end
			end
		end
	end

	return targets
end

local function applyKnockback(root: BasePart, fromPos: Vector3)
	local dir = root.Position - fromPos
	if dir.Magnitude < 0.01 then
		dir = Vector3.new(1, 0, 0)
	else
		dir = dir.Unit
	end
	root.AssemblyLinearVelocity = dir * CONFIG.KNOCKBACK + Vector3.new(0, CONFIG.UPWARD, 0)
end

-- ✅ Battle routing helpers
local function inBattlePhase2(plr: Player): boolean
	return (_G.BattleService and _G.BattleService.CanAcceptWeaponSwing and _G.BattleService.CanAcceptWeaponSwing(plr)) == true
end

local function dealBattleDamage(plr: Player, amount: number)
	if not (_G.BattleService and _G.BattleService.DealPhase2BattleDamage) then return false end
	_G.BattleService.DealPhase2BattleDamage(plr, amount)
	return true
end

-- Start cast
AbilityRequest.OnServerEvent:Connect(function(player, payload)
	if typeof(payload) ~= "table" then return end
	if payload.ability ~= "GroundSlam" then return end

	local char, hum = getCharHumRoot(player)
	if not char or hum.Health <= 0 then return end

	local st = castState[player]
	if not st then
		st = { lastCast = -1e9, castStart = -1e9 }
		castState[player] = st
	end

	local t = now()
	if t - st.lastCast < CONFIG.COOLDOWN then
		return
	end

	st.lastCast = t
	st.castStart = t

	AbilityCooldown:FireClient(player, "GroundSlam", CONFIG.COOLDOWN)
end)

-- Impact (when client triggers VFX)
AbilityImpact.OnServerEvent:Connect(function(player, payload)
	if typeof(payload) ~= "table" then return end
	if payload.ability ~= "GroundSlam" then return end

	local st = castState[player]
	if not st then return end

	local t = now()
	local dt = t - (st.castStart or -1e9)
	if dt < CONFIG.MIN_IMPACT_DELAY or dt > CONFIG.MAX_IMPACT_DELAY then
		return
	end

	local char, hum, hrp = getCharHumRoot(player)
	if not char or hum.Health <= 0 then return end

	local impactPos = groundPosFrom(hrp)

	-- ✅ If we're in a Phase2 battle window, don't use overlap queries.
	-- Battle enemy parts are CanQuery=false, so GetPartBoundsInRadius won't find them.
	if inBattlePhase2(player) then
		dealBattleDamage(player, CONFIG.DAMAGE)

		-- Optional: still apply self-contained “status feel” via VFX only.
		AbilityFX:FireAllClients({
			ability = "GroundSlam",
			origin = impactPos,
			radius = CONFIG.RADIUS,
			casterUserId = player.UserId,
			battle = true,
		})
		return
	end

	-- Overworld / non-battle: hit enemies + apply status
	local targets = findTargets(impactPos, CONFIG.RADIUS, char)
	for _, tgt in ipairs(targets) do
		tgt.hum:TakeDamage(CONFIG.DAMAGE)
		applyKnockback(tgt.root, impactPos)

		StatusService:Apply(tgt.hum, "Stun", CONFIG.STUN_DURATION)
		StatusService:Apply(tgt.hum, "Slow", 1.5, { mult = 0.6 })
		StatusService:Apply(tgt.hum, "Weakened", 2.0)
	end

	AbilityFX:FireAllClients({
		ability = "GroundSlam",
		origin = impactPos,
		radius = CONFIG.RADIUS,
		casterUserId = player.UserId,
	})
end)

Players.PlayerRemoving:Connect(function(p)
	castState[p] = nil
end)
