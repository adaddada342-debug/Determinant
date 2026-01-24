local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local openForgeEvent = ReplicatedStorage:WaitForChild("OpenForge")

-- ===== UI (Undertale-inspired) =====
local gui = Instance.new("ScreenGui")
gui.Name = "ForgeGui"
gui.ResetOnSpawn = false
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

-- ===== Sounds =====
local function cloneSound(name: string)
	local folder = ReplicatedStorage:FindFirstChild("UI_Sounds")
	if not folder then return nil end
	local s = folder:FindFirstChild(name)
	if not s or not s:IsA("Sound") then return nil end
	local c = s:Clone()
	c.Parent = gui
	return c
end

local sfxMove   = cloneSound("Move")
local sfxSelect = cloneSound("Select")
local sfxBack   = cloneSound("Back")
local sfxBlip = cloneSound("TextBlip")

local function playBlip()
	if not sfxBlip then return end
	sfxBlip.PlaybackSpeed = 1 + (math.random(-6, 6) / 100) -- slight pitch wobble
	sfxBlip:Play()
end


local function play(s: Sound?)
	if s and s.SoundId and s.SoundId ~= "" then
		s:Play()
	end
end

-- ===== Typewriter =====
local typeToken = 0
local currentFullBodyText = ""

local function stopTypewriter()
	typeToken += 1
end

local function typewrite(label: TextLabel, text: string, cps: number?)
	cps = cps or 50
	typeToken += 1
	local myToken = typeToken

	label.Text = ""
	if text == "" then return end

	local delayPerChar = 1 / cps

	for i = 1, #text do
		if myToken ~= typeToken then
			return
		end

		local char = string.sub(text, i, i)
		label.Text = string.sub(text, 1, i)

		-- only blip on visible characters
		if char ~= " " and char ~= "\n" then
			playBlip()
		end

		task.wait(delayPerChar)
	end
end


local function setBodyText(text: string)
	currentFullBodyText = text
	stopTypewriter()
	task.spawn(function()
		typewrite(script.Parent and (script.Parent :: any) and nil or nil, "", 1)
	end)
end

-- (roblox luau: we can’t typewrite until body exists; define a wrapper later)
-- We'll reassign setBodyText after body is created.

-- ===== Movement lock =====
local controls = nil
local savedHumanoidStats = { WalkSpeed = 16, JumpPower = 50, AutoRotate = true }
local movementLocked = false

local function tryGetControls()
	local ps = player:WaitForChild("PlayerScripts")
	local pm = ps:WaitForChild("PlayerModule")
	local PlayerModule = require(pm)
	return PlayerModule:GetControls()
end

task.spawn(function()
	pcall(function()
		controls = tryGetControls()
	end)
end)

local function applyHumanoidLock(locked: boolean)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	if locked then
		savedHumanoidStats.WalkSpeed = humanoid.WalkSpeed
		savedHumanoidStats.JumpPower = humanoid.JumpPower
		savedHumanoidStats.AutoRotate = humanoid.AutoRotate

		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.AutoRotate = false
	else
		humanoid.WalkSpeed = savedHumanoidStats.WalkSpeed or 16
		humanoid.JumpPower = savedHumanoidStats.JumpPower or 50
		humanoid.AutoRotate = (savedHumanoidStats.AutoRotate ~= false)
	end
end

local function lockMovement(locked: boolean)
	movementLocked = locked
	if controls then
		if locked then controls:Disable() else controls:Enable() end
	end
	applyHumanoidLock(locked)
end

player.CharacterAdded:Connect(function()
	if movementLocked then
		task.wait(0.1)
		applyHumanoidLock(true)
	end
end)

-- ===== Menu frame =====
local box = Instance.new("Frame")
box.AnchorPoint = Vector2.new(0.5, 0.5)
box.Position = UDim2.fromScale(0.5, 0.5)
box.Size = UDim2.fromScale(0.62, 0.38)
box.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
box.BorderSizePixel = 0
box.Parent = gui

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(255, 255, 255)
stroke.Thickness = 2
stroke.Parent = box

local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 16)
padding.PaddingBottom = UDim.new(0, 16)
padding.PaddingLeft = UDim.new(0, 18)
padding.PaddingRight = UDim.new(0, 18)
padding.Parent = box

local content = Instance.new("Frame")
content.BackgroundTransparency = 1
content.Size = UDim2.fromScale(1, 1)
content.Parent = box

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Size = UDim2.new(1, 0, 0, 38)
title.Position = UDim2.new(0, 0, 0, 0)
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextYAlignment = Enum.TextYAlignment.Top
title.Font = Enum.Font.Arcade
title.TextSize = 28
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "..."
title.Parent = content

local body = Instance.new("TextLabel")
body.BackgroundTransparency = 1
body.Size = UDim2.new(1, 0, 0, 84)
body.Position = UDim2.new(0, 0, 0, 44)
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextYAlignment = Enum.TextYAlignment.Top
body.TextWrapped = true
body.Font = Enum.Font.Arcade
body.TextSize = 24
body.TextColor3 = Color3.fromRGB(255, 255, 255)
body.Text = ""
body.Parent = content

-- Now that body exists, redefine setBodyText properly
setBodyText = function(text: string)
	currentFullBodyText = text
	stopTypewriter()
	task.spawn(function()
		typewrite(body, text, 50)
	end)
end

local function finishBodyInstant()
	-- Instantly finish the current typewriter line
	stopTypewriter()
	body.Text = currentFullBodyText
end

local optionsFrame = Instance.new("Frame")
optionsFrame.BackgroundTransparency = 1
optionsFrame.AnchorPoint = Vector2.new(0, 1)
optionsFrame.Position = UDim2.new(0, 0, 1, 0)
optionsFrame.Size = UDim2.new(1, 0, 0, 120)
optionsFrame.Parent = content

local list = Instance.new("UIListLayout")
list.FillDirection = Enum.FillDirection.Vertical
list.SortOrder = Enum.SortOrder.LayoutOrder
list.Padding = UDim.new(0, 10)
list.Parent = optionsFrame

-- ===== Menu builder =====
type MenuEntry = { text: string, onSelect: () -> () }

local rows = {}
local labels = {}
local markers = {}
local menuEntries: {MenuEntry} = {}
local selectedIndex = 1

local function clearOptions()
	for _, r in ipairs(rows) do
		r:Destroy()
	end
	table.clear(rows)
	table.clear(labels)
	table.clear(markers)
	table.clear(menuEntries)
	selectedIndex = 1
end

local function makeOptionRow(text: string, index: number, onSelectFn: () -> ())
	local row = Instance.new("TextButton")
	row.BackgroundTransparency = 1
	row.AutoButtonColor = false
	row.Size = UDim2.new(1, 0, 0, 30)
	row.Text = ""
	row.Selectable = false
	row.LayoutOrder = index
	row.Parent = optionsFrame

	local marker = Instance.new("TextLabel")
	marker.BackgroundTransparency = 1
	marker.Size = UDim2.new(0, 24, 1, 0)
	marker.Position = UDim2.new(0, 0, 0, 0)
	marker.Font = Enum.Font.Arcade
	marker.TextSize = 24
	marker.TextColor3 = Color3.fromRGB(255, 220, 60)
	marker.Text = " "
	marker.Parent = row

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.new(0, 28, 0, 0)
	label.Size = UDim2.new(1, -28, 1, 0)
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Font = Enum.Font.Arcade
	label.TextSize = 26
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = text
	label.Parent = row

	rows[index] = row
	labels[index] = label
	markers[index] = marker
	menuEntries[index] = { text = text, onSelect = onSelectFn }

	row.MouseEnter:Connect(function()
		local prev = selectedIndex
		selectedIndex = index
		if prev ~= selectedIndex then play(sfxMove) end
		for i = 1, #rows do
			labels[i].TextColor3 = Color3.fromRGB(255, 255, 255)
			markers[i].Text = " "
		end
		labels[selectedIndex].TextColor3 = Color3.fromRGB(255, 220, 60)
		markers[selectedIndex].Text = "♥"
	end)

	row.MouseButton1Click:Connect(function()
		selectedIndex = index
		play(sfxSelect)
		menuEntries[selectedIndex].onSelect()
	end)
end

local function setSelected(index: number)
	local newIndex = math.clamp(index, 1, #rows)
	if newIndex ~= selectedIndex then
		play(sfxMove)
	end
	selectedIndex = newIndex

	for i = 1, #rows do
		labels[i].TextColor3 = Color3.fromRGB(255, 255, 255)
		markers[i].Text = " "
	end

	labels[selectedIndex].TextColor3 = Color3.fromRGB(255, 220, 60)
	markers[selectedIndex].Text = "♥"
end

-- ===== Game state =====
local rememberedMoves = {}
local isOpen = false
local screenState = "MAIN" -- "MAIN" | "RECALL"

-- Move catalog (client-side for now; later this can come from server)
local MoveCatalog = {
	{ key = "Tough Glove", display = "TOUGH GLOVE" },
	{ key = "Practice Sword", display = "PRACTICE SWORD" },
	{ key = "Dust Burst", display = "DUST BURST" },
}

local function closeForge()
	gui.Enabled = false
	isOpen = false
	screenState = "MAIN"
	lockMovement(false)
	stopTypewriter()
end

local function buildMainMenu() end -- forward

local function buildRecallMenu()
	screenState = "RECALL"
	clearOptions()

	title.Text = "RECALL"
	setBodyText("Choose a memory.")

	for i, move in ipairs(MoveCatalog) do
		local isRemembered = rememberedMoves[move.key] == true
		local shownName = isRemembered and move.display or "???"

		makeOptionRow(shownName, i, function()
			play(sfxSelect)
			if not rememberedMoves[move.key] then
				setBodyText("You do not seem to recall the existence of that item.")
			else
				setBodyText("Your hands remember something like this.")
			end
		end)
	end

	local backIndex = #MoveCatalog + 1
	makeOptionRow("BACK", backIndex, function()
		play(sfxBack)
		buildMainMenu()
	end)

	setSelected(1)
end

buildMainMenu = function()
	screenState = "MAIN"
	clearOptions()

	title.Text = "It’s trying to remember you."
	setBodyText("...")

	makeOptionRow("RECALL", 1, function()
		play(sfxSelect)
		buildRecallMenu()
	end)

	makeOptionRow("ALTER", 2, function()
		play(sfxSelect)
		setBodyText("The memory resists being changed.")
	end)

	makeOptionRow("LEAVE", 3, function()
		play(sfxBack)
		closeForge()
	end)

	setSelected(1)
end

-- Keyboard controls (menu only)
UserInputService.InputBegan:Connect(function(input, gp)
	if not isOpen then return end
	-- ignore gp while menu is open so W/S always work

	if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.W then
		setSelected(selectedIndex - 1)

	elseif input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.S then
		setSelected(selectedIndex + 1)

	elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space then
		-- If body is still typing, finish instantly (Undertale feel)
		if body.Text ~= currentFullBodyText then
			finishBodyInstant()
			play(sfxSelect)
			return
		end

		if menuEntries[selectedIndex] and menuEntries[selectedIndex].onSelect then
			play(sfxSelect)
			menuEntries[selectedIndex].onSelect()
		end

	elseif input.KeyCode == Enum.KeyCode.Escape then
		play(sfxBack)
		if screenState == "RECALL" then
			buildMainMenu()
		else
			closeForge()
		end
	end
end)

local function openForge(serverRememberedMoves)
	rememberedMoves = serverRememberedMoves or {}

	gui.Enabled = true
	isOpen = true
	lockMovement(true)

	buildMainMenu()
end

openForgeEvent.OnClientEvent:Connect(openForge)
