-- ServerScriptService/RegionEncounterDirector.server.lua
-- Region-based random encounters (server-authoritative selection, client requests battle)
-- Works with your existing BattleService "StartTest" hook (client fires it).
-- Requires:
--   - workspace/RegionZones folder containing BaseParts that define regions
--   - Each zone part must have Attribute "RegionId" (string)
--   - StarterPlayerScripts/EncounterBridge.client.lua (below)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Remotes folder (your project already uses this pattern)
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

-- Server -> client: tells client to start a battle with a chosen enemyId
local EncounterCommandRE = Remotes:FindFirstChild("EncounterCommandRE")
if not EncounterCommandRE then
	EncounterCommandRE = Instance.new("RemoteEvent")
	EncounterCommandRE.Name = "EncounterCommandRE"
	EncounterCommandRE.Parent = Remotes
end

-- Client -> server: ack begin/end, debug, etc.
local EncounterStatusRE = Remotes:FindFirstChild("EncounterStatusRE")
if not EncounterStatusRE then
	EncounterStatusRE = Instance.new("RemoteEvent")
	EncounterStatusRE.Name = "EncounterStatusRE"
	EncounterStatusRE.Parent = Remotes
end

-- Optional: if you want to verify enemy ids exist in BattleData
local BattleData
do
	local ok, mod = pcall(function()
		return require(ReplicatedStorage:WaitForChild("BattleData"))
	end)
	if ok then
		BattleData = mod
	else
		warn("[RegionEncounterDirector] BattleData missing or failed to require:", mod)
	end
end

-- =========================
-- CONFIG
-- =========================
local CFG = {
	Debug = false,

	-- Encounter pacing
	TickRate = 0.25,             -- seconds between updates
	MinStartDelay = 2.0,          -- no encounters immediately on spawn
	EncounterCooldown = 10.0,     -- hard cooldown after triggering
	DistancePerRoll = 60.0,       -- studs traveled before a roll chance
	BaseEncounterChance = 0.35,   -- chance per roll (scaled by region modifier)

	-- Region detection
	ZoneFolderName = "RegionZones", -- workspace folder containing zone parts
	ZonePriorityAttribute = "Priority", -- optional number attribute, bigger wins when overlapping

	-- Safety
	MaxZonePartsScanned = 256,    -- sanity clamp
}

-- Region -> pools
-- IMPORTANT: enemy ids must match keys in ReplicatedStorage/BattleData.Enemies
-- Right now your BattleData only includes Froggit by default. Add more there. 
local REGION_POOLS = {
	-- Default fallback if not inside any zone
	DEFAULT = {
		chanceMult = 1.0,
		enemies = {
			{ id = "Froggit", weight = 1 },
		},
	},

	-- Example regions (rename to whatever you set as RegionId attributes)
	TOWN = {
		chanceMult = 0.55, -- calmer inside the abandoned wealthy town
		enemies = {
			{ id = "Froggit", weight = 1 },
		},
	},

	RUINS = {
		chanceMult = 1.10,
		enemies = {
			{ id = "Froggit", weight = 1 },
		},
	},

	CORRUPT_OUTSKIRTS = {
		chanceMult = 1.35,
		enemies = {
			{ id = "Froggit", weight = 1 },
		},
	},

	ISLAND_A = {
		chanceMult = 1.25,
		enemies = {
			{ id = "Froggit", weight = 1 },
		},
	},
}

-- =========================
-- UTIL
-- =========================
local function dprint(...)
	if CFG.Debug then
		print("[RegionEncounterDirector]", ...)
	end
end

local function now()
	return os.clock()
end

local function getHRP(plr: Player)
	local char = plr.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

local function pointInsidePart(part: BasePart, worldPoint: Vector3)
	-- Works for rotated parts too
	local p = part.CFrame:PointToObjectSpace(worldPoint)
	local half = part.Size * 0.5
	return math.abs(p.X) <= half.X and math.abs(p.Y) <= half.Y and math.abs(p.Z) <= half.Z
end

local function getZonesFolder()
	return workspace:FindFirstChild(CFG.ZoneFolderName)
end

local function getZonePriority(part: Instance)
	local v = part:GetAttribute(CFG.ZonePriorityAttribute)
	if typeof(v) == "number" then return v end
	return 0
end

local function chooseWeightedEnemy(list)
	-- list: { {id=string, weight=number}, ...}
	local total = 0
	for _, e in ipairs(list) do
		local w = tonumber(e.weight) or 0
		if w > 0 then total += w end
	end
	if total <= 0 then return nil end
	local r = math.random() * total
	local acc = 0
	for _, e in ipairs(list) do
		local w = tonumber(e.weight) or 0
		if w > 0 then
			acc += w
			if r <= acc then
				return e.id
			end
		end
	end
	return list[#list] and list[#list].id or nil
end

local function enemyExists(enemyId: string)
	if not BattleData or not BattleData.Enemies then
		return true -- can't verify, allow
	end
	return BattleData.Enemies[enemyId] ~= nil
end

-- =========================
-- STATE
-- =========================
type PlayerState = {
	joinedAt: number,
	lastPos: Vector3?,
	distAcc: number,
	nextAllowedAt: number,
	inEncounter: boolean,
	regionId: string,
}

local state: { [Player]: PlayerState } = {}

local function ensureState(plr: Player): PlayerState
	local s = state[plr]
	if not s then
		s = {
			joinedAt = now(),
			lastPos = nil,
			distAcc = 0,
			nextAllowedAt = now() + CFG.MinStartDelay,
			inEncounter = false,
			regionId = "DEFAULT",
		}
		state[plr] = s
	end
	return s
end

local function computeRegionForPoint(worldPoint: Vector3): string
	local zonesFolder = getZonesFolder()
	if not zonesFolder then
		return "DEFAULT"
	end

	local bestId = "DEFAULT"
	local bestPrio = -math.huge

	local scanned = 0
	for _, inst in ipairs(zonesFolder:GetChildren()) do
		if inst:IsA("BasePart") then
			scanned += 1
			if scanned > CFG.MaxZonePartsScanned then break end

			local regionId = inst:GetAttribute("RegionId")
			if typeof(regionId) == "string" and regionId ~= "" then
				if pointInsidePart(inst, worldPoint) then
					local prio = getZonePriority(inst)
					if prio > bestPrio then
						bestPrio = prio
						bestId = regionId
					end
				end
			end
		end
	end

	return bestId
end

local function getPool(regionId: string)
	local pool = REGION_POOLS[regionId]
	if pool then return pool end
	return REGION_POOLS.DEFAULT
end

local function triggerEncounter(plr: Player, enemyId: string, regionId: string)
	local s = ensureState(plr)
	if s.inEncounter then return end

	-- validate enemy id exists (if possible)
	if typeof(enemyId) ~= "string" or enemyId == "" then
		warn("[RegionEncounterDirector] Tried to trigger with blank enemyId")
		return
	end
	if not enemyExists(enemyId) then
		warn(("[RegionEncounterDirector] Unknown enemyId '%s' (add it to BattleData.Enemies)"):format(enemyId))
		return
	end

	s.inEncounter = true
	s.nextAllowedAt = now() + CFG.EncounterCooldown
	s.distAcc = 0

	dprint(("Trigger -> %s in region %s"):format(enemyId, regionId))
	EncounterCommandRE:FireClient(plr, "BeginEncounter", {
		enemyId = enemyId,
		regionId = regionId,
	})
end

-- =========================
-- CLIENT STATUS
-- =========================
EncounterStatusRE.OnServerEvent:Connect(function(plr, kind, payload)
	local s = ensureState(plr)

	if kind == "EncounterStarted" then
		-- client says it requested the battle
		s.inEncounter = true
		return
	end

	if kind == "EncounterEnded" then
		-- client says battle ended (Victory/End)
		s.inEncounter = false
		return
	end

	if kind == "SetDebug" then
		if typeof(payload) == "table" and typeof(payload.enabled) == "boolean" then
			CFG.Debug = payload.enabled
			dprint("Debug set to", CFG.Debug, "by", plr.Name)
		end
	end
end)

-- =========================
-- MAIN LOOP
-- =========================
local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < CFG.TickRate then return end
	accum = 0

	for _, plr in ipairs(Players:GetPlayers()) do
		local s = ensureState(plr)
		local hrp = getHRP(plr)
		if not hrp then
			s.lastPos = nil
			continue
		end

		local pos = hrp.Position

		-- region update
		local regionId = computeRegionForPoint(pos)
		if regionId ~= s.regionId then
			s.regionId = regionId
			dprint(plr.Name, "entered region", regionId)
			EncounterCommandRE:FireClient(plr, "RegionChanged", { regionId = regionId })
		end

		-- don't roll if in encounter or in cooldown
		if s.inEncounter then
			s.lastPos = pos
			continue
		end
		if now() < s.nextAllowedAt then
			s.lastPos = pos
			continue
		end

		-- accumulate distance traveled
		if s.lastPos then
			local moved = (pos - s.lastPos).Magnitude
			-- tiny movement noise filter
			if moved > 1.0 then
				s.distAcc += moved
			end
		end
		s.lastPos = pos

		if s.distAcc >= CFG.DistancePerRoll then
			s.distAcc -= CFG.DistancePerRoll

			local pool = getPool(s.regionId)
			local chanceMult = tonumber(pool.chanceMult) or 1.0
			local chance = math.clamp(CFG.BaseEncounterChance * chanceMult, 0, 0.95)

			local roll = math.random()
			dprint(("Roll %.3f vs chance %.3f (region %s)"):format(roll, chance, s.regionId))

			if roll <= chance then
				local enemyId = chooseWeightedEnemy(pool.enemies or REGION_POOLS.DEFAULT.enemies)
				if enemyId then
					triggerEncounter(plr, enemyId, s.regionId)
				end
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	state[plr] = nil
end)

print("[RegionEncounterDirector] Loaded. Put zone parts in workspace/RegionZones with RegionId attributes.")
