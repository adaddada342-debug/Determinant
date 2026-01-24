-- StarterPlayerScripts/Combat/BattleUI.client.lua
-- Viewport enemy + colourful UI
-- ✅ NO BattleWorld spawning (viewport only)
-- ✅ FIGHT enters Phase2 (attack mode), no click damage
-- ✅ UI hides during Phase2 + Enemy turn

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BattleRE = Remotes:WaitForChild("BattleRE")

local BattleData = require(ReplicatedStorage:WaitForChild("BattleData"))

-- Optional arena builder
local BulletHell3D
do
	local m = script.Parent:FindFirstChild("BulletHell3D")
	if m and m:IsA("ModuleScript") then
		BulletHell3D = require(m)
	end
end

local THEME = {
	BgTop = Color3.fromRGB(10, 10, 16),
	BgBottom = Color3.fromRGB(22, 6, 28),

	Text = Color3.fromRGB(245, 245, 255),

	AccentCyan = Color3.fromRGB(70, 255, 255),
	AccentMagenta = Color3.fromRGB(255, 90, 220),
	AccentPurple = Color3.fromRGB(170, 110, 255),
	AccentLime = Color3.fromRGB(120, 255, 140),

	Panel = Color3.fromRGB(0, 0, 0),
	PanelAlpha = 0.15,
}

local function mk(className, props, parent)
	local inst = Instance.new(className)
	for k, v in pairs(props) do inst[k] = v end
	inst.Parent = parent
	return inst
end

local function getHum()
	local ch = player.Character
	return ch and ch:FindFirstChildOfClass("Humanoid")
end

-- Movement lock
local savedWalkSpeed, savedJumpPower, savedAutoRotate
local MOVE_SINK = "__BATTLE_SINK_MOVE__"

local function setHumanoidLocked(on)
	local hum = getHum()
	if not hum then return end
	if on then
		savedWalkSpeed = hum.WalkSpeed
		savedJumpPower = hum.JumpPower
		savedAutoRotate = hum.AutoRotate
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum.AutoRotate = false
	else
		hum.WalkSpeed = savedWalkSpeed or 16
		hum.JumpPower = savedJumpPower or 50
		hum.AutoRotate = (savedAutoRotate ~= nil) and savedAutoRotate or true
	end
end

local function sinkMoveKeys(on)
	if on then
		ContextActionService:BindActionAtPriority(
			MOVE_SINK,
			function() return Enum.ContextActionResult.Sink end,
			false,
			9999,
			Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
			Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right
		)
	else
		ContextActionService:UnbindAction(MOVE_SINK)
	end
end

-- Arena (server teleports character; we just build visuals)
local ARENA_Y = 9000
local ARENA_SPACING = 300
local function computeArenaCenter()
	return Vector3.new((player.UserId % 50) * ARENA_SPACING, ARENA_Y, 0)
end

local arenaCenter
local function enterArena()
	arenaCenter = computeArenaCenter()
	if BulletHell3D then
		BulletHell3D:PrepareBattleArena(arenaCenter)
	end
end

local function exitArena()
	if BulletHell3D then
		BulletHell3D:TeardownBattleArena()
	end
	arenaCenter = nil
end

-- UI
local GUI_NAME = "__BattleUI"
local old = pg:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local gui = mk("ScreenGui", {
	Name = GUI_NAME,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 2500000,
	Enabled = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, pg)

local backdrop = mk("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 0,
	BorderSizePixel = 0,
	ZIndex = 1,
	Visible = false,
}, gui)
backdrop.BackgroundColor3 = THEME.BgTop
mk("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.BgTop),
		ColorSequenceKeypoint.new(1, THEME.BgBottom),
	}),
	Rotation = 90,
}, backdrop)

local viewport = mk("ViewportFrame", {
	AnchorPoint = Vector2.new(0.5, 0.35),
	Position = UDim2.new(0.5, 0, 0.35, 0),
	Size = UDim2.new(0.56, 0, 0.46, 0),
	BackgroundTransparency = 1,
	ZIndex = 5,
}, gui)

local vpCam = Instance.new("Camera")
vpCam.Parent = viewport
viewport.CurrentCamera = vpCam

local vpWorld = Instance.new("WorldModel")
vpWorld.Parent = viewport

local function clearViewport()
	for _, c in ipairs(vpWorld:GetChildren()) do c:Destroy() end
end

local function disableScripts(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") then
			d.Disabled = true
		end
	end
end

local function anchorViewportModel(m: Model)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
		end
	end
end

local function fitCameraToModel(model: Model)
	local cf, size = model:GetBoundingBox()
	local maxDim = math.max(size.X, size.Y, size.Z)
	local dist = math.clamp(maxDim * 1.7, 12, 90)
	local focus = cf.Position
	local camPos = focus + Vector3.new(0, size.Y * 0.12, dist)
	vpCam.CFrame = CFrame.new(camPos, focus)
end

local function setViewportEnemy(enemyId: string)
	clearViewport()
	local def = BattleData.Enemies[enemyId]
	local modelName = (def and def.modelName) or enemyId

	local enemiesFolder = ReplicatedStorage:FindFirstChild("Enemies")
	local src = enemiesFolder and enemiesFolder:FindFirstChild(modelName)

	local model: Model
	if src and src:IsA("Model") then
		model = src:Clone()
	else
		model = Instance.new("Model")
		model.Name = modelName
		local p = Instance.new("Part")
		p.Size = Vector3.new(6, 8, 2)
		p.Anchored = true
		p.CanCollide = false
		p.Material = Enum.Material.Neon
		p.Color = Color3.fromRGB(255, 255, 255)
		p.Parent = model
	end

	disableScripts(model)
	anchorViewportModel(model)
	model.Parent = vpWorld
	model:PivotTo(CFrame.new(0, 0, 0))
	fitCameraToModel(model)
end

local panel = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.new(0.92, 0, 0, 235),
	BackgroundTransparency = THEME.PanelAlpha,
	BackgroundColor3 = THEME.Panel,
	BorderSizePixel = 0,
	ZIndex = 10,
}, gui)

mk("UIStroke", { Color = THEME.AccentCyan, Thickness = 3 }, panel)
mk("UIStroke", { Color = THEME.AccentMagenta, Thickness = 1, Transparency = 0.65 }, panel)

local title = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 18, 0, 10),
	Size = UDim2.new(1, -36, 0, 26),
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	Font = Enum.Font.Arcade,
	TextSize = 22,
	Text = "",
	ZIndex = 11,
}, panel)

local hpBack = mk("Frame", {
	Position = UDim2.new(0, 18, 0, 40),
	Size = UDim2.new(0.62, 0, 0, 10),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255),
	BackgroundTransparency = 0.85,
	BorderSizePixel = 0,
	ZIndex = 11,
}, panel)

local hpFill = mk("Frame", {
	Size = UDim2.new(1, 0, 1, 0),
	BackgroundColor3 = THEME.AccentLime,
	BorderSizePixel = 0,
	ZIndex = 12,
}, hpBack)

mk("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.AccentLime),
		ColorSequenceKeypoint.new(1, THEME.AccentCyan),
	}),
	Rotation = 0,
}, hpFill)

local dialog = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 18, 0, 58),
	Size = UDim2.new(1, -36, 0, 106),
	TextColor3 = THEME.Text,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	Font = Enum.Font.Arcade,
	TextSize = 26,
	TextWrapped = true,
	Text = "",
	ZIndex = 11,
}, panel)

local btnRow = mk("Frame", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 0, 1, -74),
	Size = UDim2.new(1, 0, 0, 64),
	ZIndex = 12,
}, panel)

local function makeBtn(text, xScale, accent)
	local b = mk("TextButton", {
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Size = UDim2.new(0.25, 0, 1, 0),
		Position = UDim2.new(xScale, 0, 0, 0),
		Text = text,
		TextColor3 = THEME.Text,
		Font = Enum.Font.Arcade,
		TextSize = 26,
		AutoButtonColor = true,
		ZIndex = 12,
	}, btnRow)
	mk("UIStroke", { Color = accent, Thickness = 2 }, b)
	return b
end

local btnFight = makeBtn("FIGHT", 0.00, THEME.AccentMagenta)
local btnAct   = makeBtn("ACT",   0.25, THEME.AccentCyan)
local btnItem  = makeBtn("ITEM",  0.50, THEME.AccentPurple)
local btnMercy = makeBtn("MERCY", 0.75, THEME.AccentLime)

local function showUI(on)
	gui.Enabled = on
	backdrop.Visible = on
	panel.Visible = on
end

local function setMenuEnabled(on)
	for _, b in ipairs({btnFight, btnAct, btnItem, btnMercy}) do
		b.Active = on
		b.AutoButtonColor = on
		b.TextTransparency = on and 0 or 0.45
	end
end

local function setDialog(t) dialog.Text = tostring(t or "") end

local enemyId, enemyName
local enemyHP, enemyMaxHP = 0, 0
local phase = "None"
local inBattle = false
local requestedAttack = false

local function updateTop()
	title.Text = string.format("%s   HP %d/%d", tostring(enemyName or ""), enemyHP, enemyMaxHP)
	local ratio = 1
	if enemyMaxHP > 0 then ratio = math.clamp(enemyHP / enemyMaxHP, 0, 1) end
	hpFill.Size = UDim2.new(ratio, 0, 1, 0)
end

local function sendAction(payload)
	BattleRE:FireServer("Action", payload)
end

btnFight.MouseButton1Click:Connect(function()
	if phase ~= "Player" then return end
	if requestedAttack then return end
	requestedAttack = true
	setMenuEnabled(false)
	setDialog("* You move in.")
	sendAction({ type = "EnterAttack" })
end)

btnAct.MouseButton1Click:Connect(function()
	if phase ~= "Player" then return end
	setMenuEnabled(false)
	sendAction({ type = "Act", key = "Check" })
end)

btnItem.MouseButton1Click:Connect(function()
	if phase ~= "Player" then return end
	setMenuEnabled(false)
	sendAction({ type = "Item" })
end)

btnMercy.MouseButton1Click:Connect(function()
	if phase ~= "Player" then return end
	setMenuEnabled(false)
	sendAction({ type = "Mercy", choice = "Spare" })
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if not inBattle then return end
	if phase ~= "Player" then return end
	if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
		btnFight:Activate()
	end
end)

BattleRE.OnClientEvent:Connect(function(kind, payload)
	payload = payload or {}

	if kind == "Begin" then
		inBattle = true
		phase = "Player"
		requestedAttack = false

		enemyId = tostring(payload.enemyId or "")
		enemyName = tostring(payload.enemyName or enemyId)
		enemyHP = tonumber(payload.enemyHP) or 0
		enemyMaxHP = tonumber(payload.enemyMaxHP) or enemyHP

		enterArena()
		setViewportEnemy(enemyId)

		updateTop()
		setDialog(payload.intro or "* ...")

		showUI(true)
		setMenuEnabled(true)

		setHumanoidLocked(true)
		sinkMoveKeys(true)
		return
	end

	if kind == "Text" then
		setDialog(payload.line or payload.text or "")
		return
	end

	if kind == "PlayerTurn" then
		phase = "Player"
		requestedAttack = false
		enemyHP = tonumber(payload.enemyHP) or enemyHP
		enemyMaxHP = tonumber(payload.enemyMaxHP) or enemyMaxHP

		if enemyId and enemyId ~= "" then
			setViewportEnemy(enemyId)
		end

		updateTop()
		showUI(true)
		setMenuEnabled(true)

		setHumanoidLocked(true)
		sinkMoveKeys(true)
		return
	end

	if kind == "PlayerAttackBegin" then
		phase = "Phase2"
		requestedAttack = false

		showUI(false)
		setMenuEnabled(false)

		setHumanoidLocked(false)
		sinkMoveKeys(false)
		return
	end

	if kind == "DamageResult" then
		enemyHP = tonumber(payload.enemyHP) or enemyHP
		enemyMaxHP = tonumber(payload.enemyMaxHP) or enemyMaxHP
		updateTop()
		return
	end

	if kind == "EnemyTurnBegin" then
		phase = "Enemy"
		requestedAttack = false

		showUI(false)
		setMenuEnabled(false)

		setHumanoidLocked(true)
		sinkMoveKeys(false)
		return
	end

	if kind == "End" then
		inBattle = false
		phase = "None"
		requestedAttack = false

		showUI(false)
		setMenuEnabled(false)

		sinkMoveKeys(false)
		setHumanoidLocked(false)

		exitArena()

		enemyId = nil
		enemyName = nil
		enemyHP, enemyMaxHP = 0, 0
		return
	end
end)
