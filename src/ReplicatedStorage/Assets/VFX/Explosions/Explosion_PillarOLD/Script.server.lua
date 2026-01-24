-- AT_RuntimeScroll.server.lua (or .client.lua if you want client-only)
-- Drives "Untitled_Animated_Texture" created by your plugin so it keeps scrolling in play.

local RunService = game:GetService("RunService")

local root = script.Parent

-- Roblox FindFirstChild does NOT support a recursive boolean argument.
-- So we do our own small recursive finder.
local function findDescendantByName(parent: Instance, name: string): Instance?
	for _, d in ipairs(parent:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local animFolder = findDescendantByName(root, "Untitled_Animated_Texture")

if not animFolder then
	warn("[AT_RuntimeScroll] Could not find Untitled_Animated_Texture under:", root:GetFullName())
	return
end

local function findChildByNameDeep(parent: Instance, name: string): Instance?
	for _, d in ipairs(parent:GetDescendants()) do
		if d.Name == name then
			return d
		end
	end
	return nil
end

local moving = findChildByNameDeep(animFolder, "Texture_Moving")
local speedVal = moving and moving:FindFirstChild("Speed")
local speedBVal = moving and moving:FindFirstChild("SpeedB")

local function getSpeed(v: Instance?): number
	return (v and v:IsA("NumberValue")) and v.Value or 0
end

local textures = {}
local imageLabels = {}

local function rescanTargets()
	table.clear(textures)
	table.clear(imageLabels)

	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("Texture") then
			table.insert(textures, inst)
		elseif inst:IsA("ImageLabel") then
			table.insert(imageLabels, inst)
		end
	end
end

-- initial scan
rescanTargets()

-- If empty, keep scanning for a few seconds (plugin may create objects late)
if #textures == 0 and #imageLabels == 0 then
	local t0 = os.clock()
	while (#textures == 0 and #imageLabels == 0) and (os.clock() - t0 < 3) do
		task.wait(0.1)
		rescanTargets()
	end

	if #textures == 0 and #imageLabels == 0 then
		warn("[AT_RuntimeScroll] No Texture or ImageLabel found to animate under:", root:GetFullName())
	end
end

-- Runtime loop
local uOffset = 0
local vOffset = 0

-- Keep offsets bounded so they don't grow forever
local function wrapOffset(x: number): number
	-- big enough to avoid visible snapping, small enough to prevent huge floats
	if x > 1e4 or x < -1e4 then
		return 0
	end
	return x
end

RunService.Heartbeat:Connect(function(dt)
	-- If someone duplicates the model or plugin spawns new textures later,
	-- do a lightweight rescan occasionally.
	-- (Once per ~0.5s)
	if math.random() < dt * 2 then
		rescanTargets()
	end

	local sA = getSpeed(speedVal)
	local sB = getSpeed(speedBVal)

	vOffset = wrapOffset(vOffset + sA * dt)
	uOffset = wrapOffset(uOffset + sB * dt)

	for _, tex in ipairs(textures) do
		-- Texture scrolling
		tex.OffsetStudsV = vOffset
		tex.OffsetStudsU = uOffset
	end

	-- If plugin uses ImageLabels with sprite sheets
	for _, img in ipairs(imageLabels) do
		if img.ImageRectSize.X > 0 and img.ImageRectSize.Y > 0 then
			local ox = math.floor((uOffset * 60) % img.ImageRectSize.X)
			local oy = math.floor((vOffset * 60) % img.ImageRectSize.Y)
			img.ImageRectOffset = Vector2.new(ox, oy)
		end
	end
end)
