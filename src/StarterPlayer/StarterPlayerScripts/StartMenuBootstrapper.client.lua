-- StarterPlayerScripts/StartMenuBootstrap.client.lua
-- Next-gen client menu controller (single-flight, no re-open, no softlock).
-- ✅ Creates ScreenGui so there's never "void"
-- ✅ Ignores EnterMenu after game started
-- ✅ Sends ClientGameplayReady once per reqId
-- ✅ On BeginGame: force camera subject + restore controls + destroy menu GUI

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MenuAction  = Remotes:WaitForChild("MenuAction")
local MenuCommand = Remotes:WaitForChild("MenuCommand")
local MenuState   = Remotes:WaitForChild("MenuState")

-- =========================
-- ScreenGui ensure
-- =========================
local GUI_NAME = "__StartMenu_RUNTIME"
local gui = playerGui:FindFirstChild(GUI_NAME)
if not gui then
	gui = Instance.new("ScreenGui")
	gui.Name = GUI_NAME
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 999999
	gui.Parent = playerGui
end
gui.Enabled = true

-- =========================
-- Helpers
-- =========================
local function make(t, props, parent)
	local inst = Instance.new(t)
	for k,v in pairs(props or {}) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function tween(obj, goal, t)
	TweenService:Create(obj, TweenInfo.new(t or 0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
end

local function safePreload(instances)
	if type(instances) ~= "table" or #instances == 0 then return true end
	local ok = pcall(function() ContentProvider:PreloadAsync(instances) end)
	return ok
end

local function collectFolderDescendants(pathParts)
	local node = ReplicatedStorage
	for _, name in ipairs(pathParts) do
		node = node:WaitForChild(name, 10)
		if not node then return {} end
	end
	return node:GetDescendants()
end

-- =========================
-- Input + camera lock
-- =========================
local inputBlocked = false
local controls

local function blockGameplayInputs()
	if inputBlocked then return end
	inputBlocked = true

	local ps = player:WaitForChild("PlayerScripts")
	local pm = ps:FindFirstChild("PlayerModule")
	if pm then
		local ok, mod = pcall(require, pm)
		if ok and mod and mod.GetControls then
			controls = mod:GetControls()
			pcall(function() controls:Disable() end)
		end
	end

	local function sink() return Enum.ContextActionResult.Sink end
	ContextActionService:BindActionAtPriority("__MENU_KEYS__", sink, false, 99999,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
		Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
		Enum.KeyCode.E, Enum.KeyCode.Q, Enum.KeyCode.F, Enum.KeyCode.R,
		Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
		Enum.KeyCode.Tab, Enum.KeyCode.Escape
	)
end

local function unblockGameplayInputs()
	if not inputBlocked then return end
	inputBlocked = false
	ContextActionService:UnbindAction("__MENU_KEYS__")
	if controls then pcall(function() controls:Enable() end) end
	controls = nil
end

local function forceCameraToHumanoid()
	local cam = workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Custom

	local char = player.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 6)
	if hum then
		cam.CameraSubject = hum
	end
end

local function setMenuCamera()
	local cam = workspace.CurrentCamera
	if not cam then return end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.CameraSubject = nil
	-- give the camera an actual CFrame so you don't stare into the origin void
	cam.CFrame = CFrame.new(0, 15, 50) * CFrame.Angles(0, math.rad(180), 0)
end

-- =========================
-- CoreGui snapshot restore
-- =========================
local coreSnapshot = {}
local function snapshotCore()
	local types = {
		Enum.CoreGuiType.Backpack,
		Enum.CoreGuiType.Chat,
		Enum.CoreGuiType.PlayerList,
		Enum.CoreGuiType.EmotesMenu,
		Enum.CoreGuiType.Health,
	}
	for _, t in ipairs(types) do
		local ok, cur = pcall(function() return StarterGui:GetCoreGuiEnabled(t) end)
		if ok then coreSnapshot[t] = cur end
	end
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
end

local function restoreCoreBrutal()
	-- restore snapshot
	for t, cur in pairs(coreSnapshot) do
		pcall(function() StarterGui:SetCoreGuiEnabled(t, cur) end)
	end
	-- and also brute-enable everything because "still nothing" is not a vibe
	pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
end

-- =========================
-- UI
-- =========================
gui:ClearAllChildren()

local root = make("Frame", {
	Size = UDim2.fromScale(1,1),
	BackgroundColor3 = Color3.fromRGB(0,0,0),
	BorderSizePixel = 0,
}, gui)

make("UIGradient", {
	Rotation = 18,
	Color = ColorSequence.new(Color3.fromRGB(5,5,10), Color3.fromRGB(35,5,12)),
}, root)

local title = make("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 60, 0, 40),
	Size = UDim2.new(1, -120, 0, 64),
	Text = "DETERMINANT",
	Font = Enum.Font.GothamBlack,
	TextSize = 56,
	TextColor3 = Color3.fromRGB(245,245,245),
	TextXAlignment = Enum.TextXAlignment.Left,
}, root)

local status = make("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 60, 0, 108),
	Size = UDim2.new(1, -120, 0, 22),
	Text = "Waiting for server…",
	Font = Enum.Font.GothamSemibold,
	TextSize = 14,
	TextColor3 = Color3.fromRGB(255,220,140),
	TextXAlignment = Enum.TextXAlignment.Left,
	TextTransparency = 0.12,
}, root)

local panel = make("Frame", {
	Position = UDim2.new(0, 60, 0.5, -110),
	Size = UDim2.new(0, 460, 0, 250),
	BackgroundColor3 = Color3.fromRGB(10,10,14),
	BorderSizePixel = 0,
}, root)

make("UICorner", {CornerRadius=UDim.new(0,18)}, panel)
make("UIStroke", {Thickness=2, Color=Color3.fromRGB(255,220,140), Transparency=0.86}, panel)
make("UIListLayout", {
	Padding = UDim.new(0,12),
	SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Center,
}, panel)

local function mkButton(text, order)
	local b = make("TextButton", {
		Size = UDim2.new(1, -54, 0, 56),
		BackgroundColor3 = Color3.fromRGB(18,18,24),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = text,
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextColor3 = Color3.fromRGB(245,245,245),
		LayoutOrder = order,
	}, panel)
	make("UICorner", {CornerRadius=UDim.new(0,16)}, b)
	return b
end

local btnContinue = mkButton("Continue (Slot 1)", 1)
local btnNewGame  = mkButton("New Game (Slot 1)", 2)
local btnRetry    = mkButton("Retry Menu State", 3)

local function setStatus(t) status.Text = t or "" end

-- =========================
-- State machine
-- =========================
local phase = "menu"          -- "menu" | "starting" | "game"
local reqCounter = 0
local activeReqId = nil
local readySent = {}          -- [reqId] = true

local function nextReqId()
	reqCounter += 1
	return reqCounter
end

local function setButtonsEnabled(on)
	btnContinue.Active = on
	btnNewGame.Active = on
	btnRetry.Active = on
	btnContinue.AutoButtonColor = on
	btnNewGame.AutoButtonColor = on
	btnRetry.AutoButtonColor = on
	btnContinue.TextTransparency = on and 0 or 0.35
	btnNewGame.TextTransparency = on and 0 or 0.35
	btnRetry.TextTransparency = on and 0 or 0.35
end

local function enterMenu()
	phase = "menu"
	gui.Enabled = true
	setButtonsEnabled(true)
	blockGameplayInputs()
	setMenuCamera()
	snapshotCore()
end

local function leaveMenuAndDie()
	phase = "game"
	setButtonsEnabled(false)
	gui.Enabled = false
	restoreCoreBrutal()
	unblockGameplayInputs()
	forceCameraToHumanoid()

	-- destroy the menu gui so nothing can re-trap you
	gui:Destroy()
end

-- =========================
-- Bootstrap pull
-- =========================
local function pullState()
	local ok, st = pcall(function()
		return MenuState:InvokeServer()
	end)
	if ok and type(st) == "table" then
		setStatus("Menu ready.")
	else
		setStatus("MenuState failed. Check server output.")
	end
end

-- =========================
-- Buttons
-- =========================
btnRetry.MouseButton1Click:Connect(function()
	if phase ~= "menu" then return end
	setStatus("Refreshing state…")
	pullState()
end)

btnNewGame.MouseButton1Click:Connect(function()
	if phase ~= "menu" then return end
	phase = "starting"
	setButtonsEnabled(false)
	activeReqId = nextReqId()
	setStatus("Requesting new game…")
	MenuAction:FireServer("NewGame", { slot = 1, reqId = activeReqId })
end)

btnContinue.MouseButton1Click:Connect(function()
	if phase ~= "menu" then return end
	phase = "starting"
	setButtonsEnabled(false)
	activeReqId = nextReqId()
	setStatus("Requesting continue…")
	MenuAction:FireServer("Continue", { slot = 1, reqId = activeReqId })
end)

-- =========================
-- Server -> client
-- =========================
MenuCommand.OnClientEvent:Connect(function(cmd, data)
	data = data or {}
	local reqId = tonumber(data.reqId)

	-- If gameplay already started locally, ignore ANY EnterMenu attempt.
	if phase == "game" and cmd == "EnterMenu" then
		return
	end

	if cmd == "EnterMenu" then
		-- Only enter if we aren't in gameplay yet
		if phase ~= "game" then
			enterMenu()
			setStatus("Menu ready.")
		end
		return
	end

	if cmd == "Toast" then
		if phase ~= "game" then
			setStatus(tostring(data.text or "…"))
			setButtonsEnabled(true)
			phase = "menu"
		end
		return
	end

	if cmd == "ConfirmOverwrite" then
		-- minimal behavior: overwrite immediately
		if phase ~= "menu" and phase ~= "starting" then return end
		local newReq = nextReqId()
		activeReqId = newReq
		phase = "starting"
		setButtonsEnabled(false)
		setStatus("Overwriting slot…")
		MenuAction:FireServer("OverwriteSlot", { slot = data.slot, reqId = newReq })
		return
	end

	if cmd == "StartLoading" then
		-- Only accept StartLoading for the active request while starting
		if phase ~= "starting" then return end
		if activeReqId and reqId and reqId ~= activeReqId then return end

		activeReqId = reqId or activeReqId
		setStatus("Loading gameplay assets…")

		-- preload optional
		safePreload(collectFolderDescendants({"Assets","GameplayPreload"}))

		-- send ready once per reqId
		if activeReqId and not readySent[activeReqId] then
			readySent[activeReqId] = true
			setStatus("Finalizing…")
			MenuAction:FireServer("ClientGameplayReady", { reqId = activeReqId })
		end
		return
	end

	if cmd == "BeginGame" then
		-- Accept if it matches activeReqId, or if server forced
		if phase == "game" then return end
		if activeReqId and reqId and reqId ~= activeReqId then
			-- ignore a BeginGame for an old request
			return
		end

		setStatus("Spawning…")

		-- wait for character/humanoid then leave menu HARD
		local t0 = os.clock()
		while os.clock() - t0 < 10 do
			local char = player.Character
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if hum then break end
			task.wait(0.05)
		end

		leaveMenuAndDie()
		return
	end
end)

-- =========================
-- Start
-- =========================
enterMenu()
setStatus("Waiting for server…")
MenuAction:FireServer("RequestEnterMenu")
task.defer(pullState)
