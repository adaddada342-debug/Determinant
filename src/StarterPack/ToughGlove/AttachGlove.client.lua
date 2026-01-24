-- Server Script inside the Tool
-- Attaches one glove to each arm using stable pivots (GripMarker)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local tool = script.Parent
local assets = ReplicatedStorage:WaitForChild("Assets")

-- =========================
-- CONFIG (tweak only these)
-- =========================
local CONFIG = {
	RIGHT_MODEL = "ToughGlove_R",
	LEFT_MODEL  = "ToughGlove_L",

	-- Offsets are relative to the ARM CFrame.
	RIGHT_OFFSET = Vector3.new(0, -1, 0),
	RIGHT_ROT_DEG = Vector3.new(0, 0, 0),

	LEFT_OFFSET  = Vector3.new(0, -1, 0),
	LEFT_ROT_DEG = Vector3.new(0, 0, 0),

	PIVOT_NAME = "GripMarker",
	DEBUG = true,
}
-- =========================

local function dbg(...)
	if CONFIG.DEBUG then
		print("[ToughGlove]", ...)
	end
end

local function anglesDeg(v: Vector3)
	return CFrame.Angles(math.rad(v.X), math.rad(v.Y), math.rad(v.Z))
end

local function findArm(char: Model, side: "Right" | "Left"): BasePart?
	local names
	if side == "Right" then
		names = { "Right Arm", "RightArm", "RightHand", "RightLowerArm", "RightUpperArm" }
	else
		names = { "Left Arm", "LeftArm", "LeftHand", "LeftLowerArm", "LeftUpperArm" }
	end

	for _, n in ipairs(names) do
		local p = char:FindFirstChild(n)
		if p and p:IsA("BasePart") then
			return p
		end
	end
	return nil
end

local function weldAllToPivot(model: Model, pivot: BasePart)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= pivot then
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = pivot
			wc.Part1 = part
			wc.Parent = part
		end
	end
end

local function prepParts(model: Model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Massless = true
			-- keep them anchored until welds exist to avoid physics “randomness”
			part.Anchored = true
		end
	end
end

local function unanchorParts(model: Model)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end
end

local function cleanup(char: Model)
	for _, child in ipairs(char:GetChildren()) do
		if child:IsA("Model") and (child.Name == "ToughGlove_Right" or child.Name == "ToughGlove_Left") then
			child:Destroy()
		end
	end
end

local function attachOne(char: Model, side: "Right" | "Left", modelName: string, offset: Vector3, rotDeg: Vector3)
	local arm = findArm(char, side)
	if not arm then
		warn("[ToughGlove] Missing arm for", side)
		return nil
	end

	local source = assets:FindFirstChild(modelName)
	if not source or not source:IsA("Model") then
		warn("[ToughGlove] Missing model:", modelName)
		return nil
	end

	local glove = source:Clone()
	glove.Name = "ToughGlove_" .. side
	glove.Parent = char

	-- Stable pivot required
	local pivot = glove:FindFirstChild(CONFIG.PIVOT_NAME, true)
	if not (pivot and pivot:IsA("BasePart")) then
		warn("[ToughGlove] " .. modelName .. " missing pivot part '" .. CONFIG.PIVOT_NAME .. "'")
		glove:Destroy()
		return nil
	end
	glove.PrimaryPart = pivot

	prepParts(glove)

	-- Build placement CFrame in arm space
	local place = CFrame.new(offset) * anglesDeg(rotDeg)

	-- Place the glove pivot on the arm
	glove:PivotTo(arm.CFrame * place)

	-- Weld the glove together (pivot -> all parts)
	weldAllToPivot(glove, pivot)

	-- Weld pivot to the arm (this is the attachment)
	local attachWeld = Instance.new("WeldConstraint")
	attachWeld.Part0 = arm
	attachWeld.Part1 = pivot
	attachWeld.Parent = pivot

	unanchorParts(glove)

	dbg("Attached", modelName, "to", side, "arm:", arm.Name)
	return glove
end

-- Cache character because on Unequipped the tool is usually already in Backpack
local lastChar: Model? = nil
local deathConn: RBXScriptConnection? = nil
local ancestryConn: RBXScriptConnection? = nil

local function disconnectConns()
	if deathConn then deathConn:Disconnect(); deathConn = nil end
	if ancestryConn then ancestryConn:Disconnect(); ancestryConn = nil end
end

tool.Equipped:Connect(function()
	local char = tool.Parent
	if not (char and char:IsA("Model")) then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end

	lastChar = char
	cleanup(char)

	attachOne(char, "Right", CONFIG.RIGHT_MODEL, CONFIG.RIGHT_OFFSET, CONFIG.RIGHT_ROT_DEG)
	attachOne(char, "Left",  CONFIG.LEFT_MODEL,  CONFIG.LEFT_OFFSET,  CONFIG.LEFT_ROT_DEG)

	disconnectConns()

	-- Clean up if the player dies while still equipped
	deathConn = hum.Died:Connect(function()
		if lastChar then cleanup(lastChar) end
	end)

	-- Clean up if character gets removed (reset/teleport)
	ancestryConn = char.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			if lastChar then cleanup(lastChar) end
			lastChar = nil
			disconnectConns()
		end
	end)
end)

tool.Unequipped:Connect(function()
	if lastChar then
		cleanup(lastChar)
	end
	disconnectConns()
end)
