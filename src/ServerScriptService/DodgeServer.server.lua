-- ServerScriptService/DodgeRollServer.server.lua
-- ✅ AMENDED: Dodge roll that DOESN'T fling or spin on collisions
-- Fixes:
-- 1) Raycast clamp so target never goes into a wall/object
-- 2) AlignOrientation + zero angular velocity so impacts don't spin you
-- 3) Horizontal-only motion (no vertical launch)
-- 4) Safety abort if something goes wrong

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

-- Ensure Remotes folder + RemoteEvent exist
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local DodgeRollRE = Remotes:FindFirstChild("DodgeRollRE")
if not DodgeRollRE then
	DodgeRollRE = Instance.new("RemoteEvent")
	DodgeRollRE.Name = "DodgeRollRE"
	DodgeRollRE.Parent = Remotes
end

-- ========= SERVER TUNING =========
local COOLDOWN = 0.70

local DODGE_DISTANCE = 24        -- desired distance (will clamp)
local DODGE_DURATION = 0.32

local IFRAME_START = 0.05
local IFRAME_END   = 0.23

local MAX_DISTANCE = 28
local MAX_REQUEST_RATE = 6 -- per 10 seconds

local BUFFER_FROM_WALL = 1.25     -- stop short of walls
local MAX_ABORT_DISPLACEMENT = 60 -- safety if physics goes insane
-- =================================

local lastDodgeTime = {}  -- [player] = time
local requestLog = {}     -- [player] = { timestamps... }

local function now() return os.clock() end

local function logRequest(plr)
	requestLog[plr] = requestLog[plr] or {}
	local t = requestLog[plr]
	table.insert(t, now())
	for i = #t, 1, -1 do
		if (now() - t[i]) > 10 then
			table.remove(t, i)
		end
	end
	return #t
end

local function getCharParts(plr)
	local char = plr.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	if not hum or not root then return end
	return char, hum, root
end

local function setServerIFrames(char, on)
	char:SetAttribute("IFrames", on and true or false)
end

local function setDodging(char, on)
	char:SetAttribute("Dodging", on and true or false)
end

local function flatten(v: Vector3)
	return Vector3.new(v.X, 0, v.Z)
end

local function raycastClamp(char: Model, startPos: Vector3, dir: Vector3, desired: number)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	params.IgnoreWater = true

	local result = Workspace:Raycast(startPos, dir * desired, params)
	if result then
		local d = (result.Position - startPos).Magnitude
		return math.max(0, d - BUFFER_FROM_WALL)
	end
	return desired
end

local function applyDodge(plr, side)
	local char, hum, root = getCharParts(plr)
	if not char then return end
	if typeof(side) ~= "number" then return end
	side = (side < 0) and -1 or 1

	if logRequest(plr) > MAX_REQUEST_RATE then return end

	local t = now()
	local last = lastDodgeTime[plr] or -1
	if (t - last) < COOLDOWN then return end
	if hum.Health <= 0 then return end

	-- Optional anti-air to reduce chaos
	if hum.FloorMaterial == Enum.Material.Air then
		return
	end

	lastDodgeTime[plr] = t

	-- Direction based on character right, flattened
	local right = root.CFrame.RightVector
	local dir = flatten(right)
	if dir.Magnitude < 1e-3 then dir = Vector3.new(1, 0, 0) end
	dir = dir.Unit * side

	-- Clamp distance + raycast clamp
	local desired = math.clamp(DODGE_DISTANCE, 0, MAX_DISTANCE)
	local startPos = root.Position
	local clamped = raycastClamp(char, startPos, dir, desired)
	local distance = math.min(clamped, MAX_DISTANCE)

	-- If you're pressed against a wall, still do a tiny nudge so it feels responsive
	local minNudge = 3
	local effectiveDist = math.max(distance, minNudge)

	-- Lock locomotion
	local oldAutoRotate = hum.AutoRotate
	local oldWS = hum.WalkSpeed
	local oldJP = hum.JumpPower

	hum.AutoRotate = false
	hum.WalkSpeed = 0
	hum.JumpPower = 0

	setDodging(char, true)
	setServerIFrames(char, false)

	-- Goal target (invisible) we animate
	local goalPart = Instance.new("Part")
	goalPart.Name = "DodgeGoal"
	goalPart.Anchored = true
	goalPart.CanCollide = false
	goalPart.CanQuery = false
	goalPart.CanTouch = false
	goalPart.Transparency = 1
	goalPart.Size = Vector3.new(0.2, 0.2, 0.2)
	goalPart.CFrame = CFrame.new(startPos)
	goalPart.Parent = workspace

	-- Attachments
	local rootAtt = root:FindFirstChild("DodgeRootAttachment")
	if not rootAtt then
		rootAtt = Instance.new("Attachment")
		rootAtt.Name = "DodgeRootAttachment"
		rootAtt.Parent = root
	end

	local goalAtt = goalPart:FindFirstChild("DodgeGoalAttachment")
	if not goalAtt then
		goalAtt = Instance.new("Attachment")
		goalAtt.Name = "DodgeGoalAttachment"
		goalAtt.Parent = goalPart
	end

	-- AlignPosition = pull to goal
	local align = Instance.new("AlignPosition")
	align.Name = "DodgeAlignPosition"
	align.Attachment0 = rootAtt
	align.Attachment1 = goalAtt
	align.RigidityEnabled = false
	align.ReactionForceEnabled = false
	align.ApplyAtCenterOfMass = true

	-- Important: don’t use “infinite anger”
	align.MaxForce = 250000        -- lowered from 1e9 to prevent flings
	align.Responsiveness = 60      -- still snappy, less explosive
	align.Parent = root

	-- AlignOrientation = stop spin
	local ori = Instance.new("AlignOrientation")
	ori.Name = "DodgeAlignOrientation"
	ori.Attachment0 = rootAtt
	ori.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ori.RigidityEnabled = false
	ori.ReactionTorqueEnabled = false
	ori.MaxTorque = 250000
	ori.Responsiveness = 80
	ori.PrimaryAxisOnly = false
	ori.CFrame = root.CFrame -- lock current facing
	ori.Parent = root

	-- Progress driver
	local prog = Instance.new("NumberValue")
	prog.Value = 0
	prog.Name = "DodgeProgress"
	prog.Parent = goalPart

	local tween = TweenService:Create(
		prog,
		TweenInfo.new(DODGE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = 1 }
	)

	local startT = now()
	local endT = startT + DODGE_DURATION
	local ifStartT = startT + IFRAME_START
	local ifEndT = startT + IFRAME_END

	-- Horizontal-only target, keep Y stable
	local targetPos = startPos + (dir * effectiveDist)
	targetPos = Vector3.new(targetPos.X, startPos.Y, targetPos.Z)

	local hbConn
	hbConn = RunService.Heartbeat:Connect(function()
		if not char.Parent or not root.Parent or hum.Health <= 0 then
			if hbConn then hbConn:Disconnect() end
			return
		end

		local tn = now()

		-- Drive goal (horizontal only)
		local p = prog.Value
		local eased = startPos:Lerp(targetPos, p)
		eased = Vector3.new(eased.X, startPos.Y, eased.Z)
		goalPart.CFrame = CFrame.new(eased)

		-- Kill spin (collision torque is the main “rotate like a beyblade” culprit)
		root.AssemblyAngularVelocity = Vector3.zero

		-- IFrames window
		setServerIFrames(char, tn >= ifStartT and tn <= ifEndT)

		-- Safety abort if something went off the rails
		if (root.Position - startPos).Magnitude > MAX_ABORT_DISPLACEMENT then
			if hbConn then hbConn:Disconnect() end
		end

		if tn >= endT then
			if hbConn then hbConn:Disconnect() end
		end
	end)

	tween:Play()

	task.delay(DODGE_DURATION + 0.06, function()
		if hbConn then hbConn:Disconnect() end
		setServerIFrames(char, false)
		setDodging(char, false)

		if align and align.Parent then align:Destroy() end
		if ori and ori.Parent then ori:Destroy() end
		if goalPart and goalPart.Parent then goalPart:Destroy() end

		if hum and hum.Parent then
			hum.AutoRotate = oldAutoRotate
			hum.WalkSpeed = oldWS
			hum.JumpPower = oldJP
		end
	end)
end

DodgeRollRE.OnServerEvent:Connect(function(plr, side)
	applyDodge(plr, side)
end)

Players.PlayerRemoving:Connect(function(plr)
	lastDodgeTime[plr] = nil
	requestLog[plr] = nil
end)

print("[DodgeRollServer] Loaded (clamped + no fling + no spin).")
