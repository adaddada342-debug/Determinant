-- StarterPlayerScripts/BattlePrompt.client.lua
-- Undertale-style pre-fight confirmation popup (client-side only).
-- Does NOT change battle pipeline; you call _G.BattlePrompt(enemyId) to start via server StartTest.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BattleRE = Remotes:WaitForChild("BattleRE")

local BattleData = require(ReplicatedStorage:WaitForChild("BattleData"))

local GUI_NAME = "__BattlePrompt"
local ACTION_BLOCK = "__BATTLE_PROMPT_BLOCK__"

local function mk(t, props, parent)
	local o = Instance.new(t)
	for k, v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end

local function tw(obj, goal, dur, style, dir)
	local ti = TweenInfo.new(dur or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local t = TweenService:Create(obj, ti, goal)
	t:Play()
	return t
end

local gui = pg:FindFirstChild(GUI_NAME)
if gui then gui:Destroy() end

gui = mk("ScreenGui", {
	Name = GUI_NAME,
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 2499999, -- just under your BattleUI (2500000)
	Enabled = false,
}, pg)

local shade = mk("Frame", {
	Size = UDim2.fromScale(1,1),
	BackgroundColor3 = Color3.fromRGB(0,0,0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 1,
}, gui)

local boxOuter = mk("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.62),
	Size = UDim2.new(0, 720, 0, 170),
	BackgroundColor3 = Color3.fromRGB(245,245,245),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 2,
}, gui)

local box = mk("Frame", {
	Position = UDim2.new(0, 6, 0, 6),
	Size = UDim2.new(1, -12, 1, -12),
	BackgroundColor3 = Color3.fromRGB(0,0,0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 3,
}, boxOuter)

local msg = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 18, 0, 16),
	Size = UDim2.new(1, -36, 0, 80),
	Text = "",
	Font = Enum.Font.Arcade,
	TextSize = 22,
	TextColor3 = Color3.fromRGB(245,245,245),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
	ZIndex = 4,
}, box)

local hint = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 18, 1, -44),
	Size = UDim2.new(1, -36, 0, 26),
	Text = "ENTER: confirm    ESC: cancel",
	Font = Enum.Font.Arcade,
	TextSize = 18,
	TextColor3 = Color3.fromRGB(255, 240, 90),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 4,
}, box)

local caret = mk("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 18, 1, -58),
	Size = UDim2.new(0, 24, 0, 24),
	Text = ">",
	Font = Enum.Font.Arcade,
	TextSize = 20,
	TextColor3 = Color3.fromRGB(255, 240, 90),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Center,
	ZIndex = 5,
	Visible = false,
}, box)

local function blockInput(on)
	ContextActionService:UnbindAction(ACTION_BLOCK)
	if not on then return end
	ContextActionService:BindActionAtPriority(
		ACTION_BLOCK,
		function() return Enum.ContextActionResult.Sink end,
		false,
		999997
	)
end

local promptOpen = false
local pendingEnemyId = nil
local resolveFn = nil

local function closePrompt()
	promptOpen = false
	pendingEnemyId = nil
	resolveFn = nil
	caret.Visible = false

	tw(shade, {BackgroundTransparency = 1}, 0.12)
	tw(boxOuter, {BackgroundTransparency = 1}, 0.12)
	tw(box, {BackgroundTransparency = 1}, 0.12)

	task.delay(0.14, function()
		gui.Enabled = false
		blockInput(false)
	end)
end

local function openPrompt(enemyId)
	local enemy = BattleData.Enemies[enemyId]
	local enemyName = enemy and enemy.name or enemyId

	promptOpen = true
	pendingEnemyId = enemyId

	gui.Enabled = true
	blockInput(true)

	msg.Text = ("* %s blocks your path.\n* Proceed?"):format(enemyName)

	shade.BackgroundTransparency = 1
	boxOuter.BackgroundTransparency = 1
	box.BackgroundTransparency = 1

	tw(shade, {BackgroundTransparency = 0.35}, 0.12)
	tw(boxOuter, {BackgroundTransparency = 0}, 0.12)
	tw(box, {BackgroundTransparency = 0}, 0.12)

	-- little “heartbeat” caret blink
	caret.Visible = true
end

-- keyboard handling
local function bindNav()
	ContextActionService:UnbindAction(GUI_NAME.."_NAV")
	ContextActionService:BindActionAtPriority(GUI_NAME.."_NAV", function(_, state, input)
		if state ~= Enum.UserInputState.Begin then
			return Enum.ContextActionResult.Sink
		end
		if not promptOpen then
			return Enum.ContextActionResult.Pass
		end

		local kc = input.KeyCode
		if kc == Enum.KeyCode.Return or kc == Enum.KeyCode.KeypadEnter then
			local fn = resolveFn
			local id = pendingEnemyId
			closePrompt()
			if fn then fn(true, id) end
			return Enum.ContextActionResult.Sink
		elseif kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.Backspace then
			local fn = resolveFn
			local id = pendingEnemyId
			closePrompt()
			if fn then fn(false, id) end
			return Enum.ContextActionResult.Sink
		end

		return Enum.ContextActionResult.Sink
	end, false, 999998,
	Enum.KeyCode.Return, Enum.KeyCode.KeypadEnter,
	Enum.KeyCode.Escape, Enum.KeyCode.Backspace
	)
end
bindNav()

-- caret blink
local blinkT = 0
RunService.RenderStepped:Connect(function(dt)
	if not promptOpen then return end
	blinkT += dt
	local on = (math.floor(blinkT * 2) % 2) == 0
	caret.TextTransparency = on and 0 or 0.65
end)

-- Public API:
-- Call _G.BattlePrompt("Froggit") and it will show the popup, then fire StartTest if confirmed.
_G.BattlePrompt = function(enemyId)
	enemyId = tostring(enemyId or "")
	if enemyId == "" then return end
	if promptOpen then return end

	openPrompt(enemyId)

	resolveFn = function(confirmed, id)
		if confirmed then
			BattleRE:FireServer("StartTest", { enemyId = id })
		end
	end
end
