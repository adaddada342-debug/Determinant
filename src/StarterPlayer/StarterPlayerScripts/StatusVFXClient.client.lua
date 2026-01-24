-- StarterPlayerScripts/StatusVFXClient
-- Shows simple status VFX above humanoids based on server StatusEvent packets.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local StatusEvent = remotes:WaitForChild("StatusEvent")

local player = Players.LocalPlayer

-- =========================
-- CONFIG: look + behaviour
-- =========================
local CONFIG = {
	HEIGHT = 3.2,          -- how high above head
	MAX_DISTANCE = 180,    -- don’t render far targets
	UPDATE_RATE = 0.1,     -- timer UI refresh
}

-- One folder per humanoid to hold effects
-- active[humanoid] = { folder = Instance, statuses = { [name] = { expiresAt, vfxFolder } } }
local active = {}

local function now() return os.clock() end

local function getRoot(model: Model)
	return model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Head")
end

local function distanceToLocal(pos: Vector3)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return math.huge end
	return (hrp.Position - pos).Magnitude
end

local function ensureHolder(hum: Humanoid)
	local model = hum.Parent
	if not model or not model:IsA("Model") then return nil end

	local root = getRoot(model)
	if not root or not root:IsA("BasePart") then return nil end

	local record = active[hum]
	if record and record.folder and record.folder.Parent then
		return record, root
	end

	local holder = Instance.new("Folder")
	holder.Name = "StatusVFX"
	holder.Parent = model

	record = { folder = holder, statuses = {} }
	active[hum] = record

	-- cleanup if model dies or removed
	hum.AncestryChanged:Connect(function()
		if hum.Parent == nil then
			active[hum] = nil
		end
	end)

	return record, root
end

-- =========================
-- VFX builders (cheap + readable)
-- =========================

local function makeBillboard(root: BasePart, text: string)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Billboard"
	bb.Adornee = root
	bb.Size = UDim2.fromOffset(120, 40)
	bb.StudsOffset = Vector3.new(0, CONFIG.HEIGHT, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = CONFIG.MAX_DISTANCE

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextStrokeTransparency = 0.2
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = text
	label.Parent = bb

	return bb, label
end

local function makeRing(root: BasePart, name: string, color: Color3, transparency: number)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Shape = Enum.PartType.Cylinder
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(0.12, 2.2, 2.2)

	-- follow using AlignPosition/AlignOrientation? we’ll keep it simple: Heartbeat weld-ish updater
	p.Parent = root.Parent

	return p
end

local function attachUpdater(root: BasePart, part: BasePart, yOffset: number, spinSpeed: number)
	local alive = true
	local angle = 0

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if not alive then return end
		if not root.Parent or not part.Parent then
			alive = false
			if conn then conn:Disconnect() end
			return
		end
		angle += dt * spinSpeed
		part.CFrame = CFrame.new(root.Position + Vector3.new(0, yOffset, 0)) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, angle, 0)
	end)

	return function()
		alive = false
		if conn then conn:Disconnect() end
	end
end

-- STUN: stars + “STUN” label
local function buildStun(root: BasePart)
	local folder = Instance.new("Folder")
	folder.Name = "StunVFX"

	local bb, label = makeBillboard(root, "STUN")
	bb.Parent = folder

	local ring = makeRing(root, "StunRing", Color3.fromRGB(255, 245, 130), 0.25)
	ring.Parent = folder

	local stopUpdate = attachUpdater(root, ring, CONFIG.HEIGHT - 0.3, 6.0)

	return folder, label, function()
		stopUpdate()
	end
end

-- SLOW: icy ring + “SLOW”
local function buildSlow(root: BasePart)
	local folder = Instance.new("Folder")
	folder.Name = "SlowVFX"

	local bb, label = makeBillboard(root, "SLOW")
	-- make it a little colder visually
	label.TextColor3 = Color3.fromRGB(170, 220, 255)
	bb.Parent = folder

	local ring = makeRing(root, "SlowRing", Color3.fromRGB(120, 200, 255), 0.35)
	ring.Parent = folder
	local stopUpdate = attachUpdater(root, ring, CONFIG.HEIGHT - 0.55, 2.5)

	return folder, label, function()
		stopUpdate()
	end
end

-- WEAKENED: purple ring + “WEAK”
local function buildWeakened(root: BasePart)
	local folder = Instance.new("Folder")
	folder.Name = "WeakenedVFX"

	local bb, label = makeBillboard(root, "WEAK")
	label.TextColor3 = Color3.fromRGB(215, 160, 255)
	bb.Parent = folder

	local ring = makeRing(root, "WeakRing", Color3.fromRGB(180, 90, 255), 0.40)
	ring.Parent = folder
	local stopUpdate = attachUpdater(root, ring, CONFIG.HEIGHT - 0.45, 3.3)

	return folder, label, function()
		stopUpdate()
	end
end

local BUILDERS = {
	Stun = buildStun,
	Slow = buildSlow,
	Weakened = buildWeakened,
}

local function removeStatus(hum: Humanoid, statusName: string)
	local rec = active[hum]
	if not rec then return end
	local s = rec.statuses[statusName]
	if not s then return end

	if s.stop then
		pcall(s.stop)
	end
	if s.vfxFolder and s.vfxFolder.Parent then
		s.vfxFolder:Destroy()
	end

	rec.statuses[statusName] = nil

	-- if empty, cleanup holder
	if next(rec.statuses) == nil and rec.folder and rec.folder.Parent then
		rec.folder:Destroy()
		active[hum] = nil
	end
end

local function applyStatus(hum: Humanoid, statusName: string, seconds: number)
	local rec, root = ensureHolder(hum)
	if not rec or not root then return end

	-- distance cull
	if distanceToLocal(root.Position) > CONFIG.MAX_DISTANCE then
		return
	end

	local builder = BUILDERS[statusName]
	if not builder then
		return
	end

	local expiresAt = now() + math.max(0, seconds)

	-- already exists -> just update expiry
	local existing = rec.statuses[statusName]
	if existing then
		existing.expiresAt = expiresAt
		return
	end

	local vfxFolder, label, stopFn = builder(root)
	vfxFolder.Parent = rec.folder

	rec.statuses[statusName] = {
		expiresAt = expiresAt,
		vfxFolder = vfxFolder,
		label = label,
		stop = stopFn,
	}
end

-- Server sends: StatusEvent:FireAllClients(humanoid, { Stun = 0.3, Slow = 1.2, ... })
StatusEvent.OnClientEvent:Connect(function(hum, packet)
	if typeof(hum) ~= "Instance" or not hum:IsA("Humanoid") then return end
	if typeof(packet) ~= "table" then return end

	-- Apply/update statuses in packet
	for statusName, remaining in pairs(packet) do
		if typeof(statusName) == "string" and typeof(remaining) == "number" then
			if remaining > 0 then
				applyStatus(hum, statusName, remaining)
			else
				removeStatus(hum, statusName)
			end
		end
	end
end)

-- Timer cleanup + small “time left” on label
local accum = 0
RunService.Heartbeat:Connect(function(dt)
	accum += dt
	if accum < CONFIG.UPDATE_RATE then return end
	accum = 0

	local t = now()
	for hum, rec in pairs(active) do
		if hum.Parent == nil or rec.folder.Parent == nil then
			active[hum] = nil
			continue
		end

		for statusName, s in pairs(rec.statuses) do
			local remaining = s.expiresAt - t
			if remaining <= 0 then
				removeStatus(hum, statusName)
			else
				if s.label then
					s.label.Text = string.format("%s %.1fs", string.upper(statusName), remaining)
				end
			end
		end
	end
end)
