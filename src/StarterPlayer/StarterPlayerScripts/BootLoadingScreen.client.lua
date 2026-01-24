-- StarterPlayerScripts/BootLoadingScreen.client.lua
-- Simple boot loader:
-- ✅ Hides other GUIs while loading
-- ✅ Preloads ReplicatedStorage.Assets (sounds/images/meshes/textures/etc.)
-- ✅ Shows progress bar + status
-- ✅ Restores GUIs when done (your start screen will appear)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

-- ----------------------------
-- CONFIG
-- ----------------------------
local CFG = {
	ASSETS_PATH = {"Assets"},     -- ReplicatedStorage/Assets
	MIN_SHOW_TIME = 1.2,          -- don't blink the loading screen (seconds)
	FADE_OUT_TIME = 0.25,
	TITLE = "DETERMINANT",
	SUBTITLE = "Loading assets...",
}

-- ----------------------------
-- GUI (created at runtime)
-- ----------------------------
local function makeGui(pg: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "__BootLoading"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 9e9
	gui.Parent = pg

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	root.BackgroundTransparency = 0
	root.BorderSizePixel = 0
	root.Parent = gui

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 80)
	title.Position = UDim2.new(0, 0, 0.34, 0)
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.Text = CFG.TITLE
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.Parent = root

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Size = UDim2.new(1, 0, 0, 40)
	subtitle.Position = UDim2.new(0, 0, 0.34, 80)
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextScaled = true
	subtitle.Text = CFG.SUBTITLE
	subtitle.TextColor3 = Color3.fromRGB(210, 210, 210)
	subtitle.Parent = root

	local barBack = Instance.new("Frame")
	barBack.AnchorPoint = Vector2.new(0.5, 0)
	barBack.Position = UDim2.fromScale(0.5, 0.52)
	barBack.Size = UDim2.fromScale(0.55, 0.018)
	barBack.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	barBack.BorderSizePixel = 0
	barBack.Parent = root

	local barFill = Instance.new("Frame")
	barFill.Size = UDim2.fromScale(0, 1)
	barFill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	barFill.BorderSizePixel = 0
	barFill.Parent = barBack

	local pct = Instance.new("TextLabel")
	pct.BackgroundTransparency = 1
	pct.Size = UDim2.new(1, 0, 0, 30)
	pct.Position = UDim2.new(0, 0, 0.52, 22)
	pct.Font = Enum.Font.GothamMedium
	pct.TextScaled = true
	pct.Text = "0%"
	pct.TextColor3 = Color3.fromRGB(180, 180, 180)
	pct.Parent = root

	return gui, root, subtitle, barFill, pct
end

-- ----------------------------
-- Hide/Restore other GUIs
-- ----------------------------
local function suppressOtherScreenGuis(pg: PlayerGui, keepName: string)
	local prev = {}
	for _, inst in ipairs(pg:GetChildren()) do
		if inst:IsA("ScreenGui") and inst.Name ~= keepName then
			prev[inst] = inst.Enabled
			inst.Enabled = false
		end
	end
	return prev
end

local function restoreScreenGuis(prev)
	for gui, wasEnabled in pairs(prev) do
		if gui and gui.Parent then
			gui.Enabled = wasEnabled
		end
	end
end

-- ----------------------------
-- Asset collection (preload targets)
-- ----------------------------
local function getByPath(root: Instance, path: {string})
	local cur: Instance? = root
	for _, name in ipairs(path) do
		if not cur then return nil end
		cur = cur:FindFirstChild(name)
	end
	return cur
end

local function collectPreloadTargets(root: Instance): {Instance}
	-- ContentProvider:PreloadAsync accepts instances; it will preload associated asset content.
	-- We'll gather likely-asset-holders plus the root container.
	local targets = {root}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Decal")
			or d:IsA("Texture")
			or d:IsA("ImageLabel")
			or d:IsA("ImageButton")
			or d:IsA("Sound")
			or d:IsA("Animation")
			or d:IsA("MeshPart")
			or d:IsA("SpecialMesh")
			or d:IsA("ParticleEmitter")
			or d:IsA("Beam")
			or d:IsA("Trail")
		then
			table.insert(targets, d)
		end
	end
	return targets
end

-- ----------------------------
-- Main
-- ----------------------------
task.spawn(function()
	local pg = player:WaitForChild("PlayerGui")

	local gui, root, subtitle, barFill, pct = makeGui(pg)
	local prevStates = suppressOtherScreenGuis(pg, gui.Name)

	local startedAt = os.clock()

	-- Find assets root
	local assetsRoot = getByPath(ReplicatedStorage, CFG.ASSETS_PATH)
	if not assetsRoot then
		subtitle.Text = "Assets folder missing. Skipping preload..."
		task.wait(1.0)
		restoreScreenGuis(prevStates)
		gui:Destroy()
		return
	end

	local targets = collectPreloadTargets(assetsRoot)
	local total = math.max(1, #targets)
	local loaded = 0

	local function setProgress(n: number)
		local p = math.clamp(n / total, 0, 1)
		barFill.Size = UDim2.fromScale(p, 1)
		pct.Text = tostring(math.floor(p * 100 + 0.5)) .. "%"
	end

	setProgress(0)
	subtitle.Text = "Loading assets..."

	-- Preload with callback; callback can fire multiple times per asset id.
	-- We'll just count callbacks but clamp at total to keep UI sane.
	local ok, err = pcall(function()
		ContentProvider:PreloadAsync(targets, function(_assetId, _status)
			loaded = math.min(total, loaded + 1)
			setProgress(loaded)
			-- keep UI responsive
			if loaded % 10 == 0 then RunService.Heartbeat:Wait() end
		end)
	end)

	if not ok then
		subtitle.Text = "Preload failed, continuing anyway..."
		warn("[BootLoading] PreloadAsync error:", err)
	end

	-- Ensure it shows for at least a moment
	local elapsed = os.clock() - startedAt
	if elapsed < CFG.MIN_SHOW_TIME then
		task.wait(CFG.MIN_SHOW_TIME - elapsed)
	end

	setProgress(total)
	subtitle.Text = "Ready."

	-- Fade out
	local t = TweenService:Create(root, TweenInfo.new(CFG.FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1
	})
	t:Play()

	-- Also fade text a bit
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("TextLabel") then
			TweenService:Create(child, TweenInfo.new(CFG.FADE_OUT_TIME), {TextTransparency = 1}):Play()
		end
	end

	task.wait(CFG.FADE_OUT_TIME + 0.05)

	restoreScreenGuis(prevStates)
	if gui and gui.Parent then gui:Destroy() end
end)
