-- StarterPlayerScripts/ForgeBackpack.client.lua
-- Inventory UI (NOT "Forge" anything):
-- ✅ Tabs always visible
-- ✅ Uses server InventoryRF with itemId (Equip/Get)
-- ✅ Filtering reads item.attrs.ItemType
-- ✅ No stat junk panel, just clean dramatic info
-- ✅ Fires HUDInventorySignal RemoveFromHUD only when inventory click UNEQUIPS
-- ✅ No blur, no Lighting changes
-- ✅ NEW: Auto-hides whenever Combat UI opens (via __CombatUIBridge)
-- ✅ NEW: Prevents toggling inventory while Combat UI is open
-- ✅ Visual polish: more Undertale-ish borders (white outline, black fill, less rounded)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
end)

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local InventoryRF = Remotes:WaitForChild("InventoryRF")
local InventoryRE = Remotes:WaitForChild("InventoryRE")

local function mk(t, props, parent)
	local o = Instance.new(t)
	for k, v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end

-- Shared local signal used by HUD (client-only)
local function getHudSignal()
	local pg = player:WaitForChild("PlayerGui")
	local ev = pg:FindFirstChild("HUDInventorySignal")
	if not ev then
		ev = Instance.new("BindableEvent")
		ev.Name = "HUDInventorySignal"
		ev.Parent = pg
	end
	return ev
end
local HUDSignal = getHudSignal()

-- ====== THEME (black/red/yellow, aggressive) ======
local C_BG      = Color3.fromRGB(0, 0, 0)
local C_PANEL   = Color3.fromRGB(0, 0, 0)
local C_PANEL2  = Color3.fromRGB(0, 0, 0)
local C_WHITE   = Color3.fromRGB(245, 245, 245)
local C_MUTE    = Color3.fromRGB(175, 175, 190)

local C_RED     = Color3.fromRGB(255, 70, 70)
local C_YEL     = Color3.fromRGB(255, 210, 90)
local C_GOLD    = Color3.fromRGB(255, 170, 40)

local C_ACC1    = C_RED
local C_ACC2    = C_YEL
local C_ACC3    = C_GOLD

local RARITY_COLORS = {
	Common = Color3.fromRGB(190,190,200),
	Uncommon = Color3.fromRGB(120,255,170),
	Rare = Color3.fromRGB(110,170,255),
	Epic = Color3.fromRGB(190,110,255),
	Legendary = Color3.fromRGB(255,190,90),
	Mythic = Color3.fromRGB(255,90,120),
}

local function rarityColor(r)
	return RARITY_COLORS[tostring(r)] or RARITY_COLORS.Common
end

-- ====== COMBAT UI VISIBILITY HOOK ======
local function getCombatBridge()
	local pg = player:WaitForChild("PlayerGui")
	local ev = pg:FindFirstChild("__CombatUIBridge")
	if not ev then
		-- Combat script creates it; but if load order is weird, we’ll wait briefly.
		ev = pg:WaitForChild("__CombatUIBridge", 10)
	end
	return ev
end

local combatOpen = false
local function setCombatOpen(on)
	combatOpen = on == true
end

-- ====== GUI ROOT ======
local gui = mk("ScreenGui", {
	Name = "InventoryUI",
	ResetOnSpawn = false,
	IgnoreGuiInset = true
}, player:WaitForChild("PlayerGui"))

-- overlay for scanlines/noise
local overlay = mk("Frame", {
	Name = "Overlay",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1,1)
}, gui)

local scan = mk("Frame", {
	Name = "Scan",
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1,1),
	Visible = true
}, overlay)

local scanGrad = mk("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(C_WHITE, C_WHITE),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 0.92),
		NumberSequenceKeypoint.new(0.48, 0.92),
		NumberSequenceKeypoint.new(0.50, 0.84),
		NumberSequenceKeypoint.new(0.52, 0.92),
		NumberSequenceKeypoint.new(1.00, 0.92),
	}),
	Offset = Vector2.new(0,0),
}, scan)

local noise = mk("Frame", {
	Name = "Noise",
	BackgroundColor3 = C_WHITE,
	BackgroundTransparency = 0.985,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1,1),
	Visible = true
}, overlay)

local noiseGrad = mk("UIGradient", {
	Rotation = 35,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255,255,255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200,200,210)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255,255,255)),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.96),
		NumberSequenceKeypoint.new(0.5, 0.99),
		NumberSequenceKeypoint.new(1, 0.96),
	}),
	Offset = Vector2.new(0,0),
}, noise)

-- ====== OPEN BUTTON (more Undertale-ish: white border, black fill, sharper) ======
local openBtn = mk("TextButton", {
	Name = "OpenInventory",
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 22, 1, -22),
	Size = UDim2.new(0, 220, 0, 58),
	BackgroundColor3 = C_WHITE,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "INVENTORY  [B]",
	Font = Enum.Font.Arcade,
	TextSize = 18,
	TextColor3 = C_GOLD,
}, gui)

local openInner = mk("Frame", {
	BackgroundColor3 = C_PANEL,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 4, 0, 4),
	Size = UDim2.new(1, -8, 1, -8),
}, openBtn)

openBtn.TextTransparency = 0 -- text on button itself is fine

-- ====== MAIN WINDOW ======
local window = mk("Frame", {
	Name = "Window",
	BackgroundTransparency = 1,
	Visible = false,
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(0, 920, 0, 560)
}, gui)

-- Outer white border
local panelOuter = mk("Frame", {
	Name = "PanelOuter",
	BackgroundColor3 = C_WHITE,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1,1),
}, window)

local panel = mk("Frame", {
	Name = "Panel",
	BackgroundColor3 = C_BG,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 6, 0, 6),
	Size = UDim2.new(1, -12, 1, -12)
}, panelOuter)

local innerOuter = mk("Frame", {
	Name = "InnerOuter",
	BackgroundColor3 = C_WHITE,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5,0.5),
	Position = UDim2.fromScale(0.5,0.5),
	Size = UDim2.new(1, -18, 1, -18),
}, panel)

local inner = mk("Frame", {
	Name = "Inner",
	BackgroundColor3 = C_PANEL,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 4, 0, 4),
	Size = UDim2.new(1, -8, 1, -8),
}, innerOuter)

local title = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 22, 0, 14),
	Size = UDim2.new(1, -44, 0, 34),
	Text = "INVENTORY",
	Font = Enum.Font.Arcade,
	TextSize = 28,
	TextColor3 = C_WHITE,
	TextXAlignment = Enum.TextXAlignment.Left,
}, inner)

local sub = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 24, 0, 48),
	Size = UDim2.new(1, -48, 0, 18),
	Text = "Weapons • Armour • Runes • Other",
	Font = Enum.Font.Code,
	TextSize = 14,
	TextColor3 = C_MUTE,
	TextXAlignment = Enum.TextXAlignment.Left,
}, inner)

local close = mk("TextButton", {
	AnchorPoint = Vector2.new(1,0),
	Position = UDim2.new(1, -16, 0, 16),
	Size = UDim2.new(0, 44, 0, 44),
	BackgroundColor3 = C_WHITE,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "X",
	Font = Enum.Font.Arcade,
	TextSize = 18,
	TextColor3 = C_RED,
}, inner)

local closeInner = mk("Frame", {
	BackgroundColor3 = C_PANEL,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 4, 0, 4),
	Size = UDim2.new(1, -8, 1, -8),
}, close)

-- left: tabs
local tabs = mk("Frame", {
	Name = "Tabs",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 18, 0, 80),
	Size = UDim2.new(0, 220, 1, -98),
}, inner)

mk("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, tabs)

-- right: details panel (minimal, no stats)
local detailsOuter = mk("Frame", {
	Name = "DetailsOuter",
	BackgroundColor3 = C_WHITE,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(1,0),
	Position = UDim2.new(1, -18, 0, 80),
	Size = UDim2.new(0, 260, 1, -98),
}, inner)

local details = mk("Frame", {
	Name = "Details",
	BackgroundColor3 = C_PANEL2,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 4, 0, 4),
	Size = UDim2.new(1, -8, 1, -8),
}, detailsOuter)

local detTitle = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 14),
	Size = UDim2.new(1, -32, 0, 22),
	Text = "SELECT AN ITEM",
	Font = Enum.Font.Arcade,
	TextSize = 16,
	TextColor3 = C_WHITE,
	TextXAlignment = Enum.TextXAlignment.Left,
}, details)

local detInfo = mk("TextLabel", {
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 16, 0, 44),
	Size = UDim2.new(1, -32, 1, -120),
	Text = "Pick something.\nPreferably something dangerous.",
	Font = Enum.Font.Code,
	TextSize = 13,
	TextColor3 = C_MUTE,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	TextWrapped = true,
}, details)

local equipBtnOuter = mk("Frame", {
	AnchorPoint = Vector2.new(0.5,1),
	Position = UDim2.new(0.5, 0, 1, -16),
	Size = UDim2.new(1, -32, 0, 52),
	BackgroundColor3 = C_WHITE,
	BorderSizePixel = 0,
}, details)

local equipBtn = mk("TextButton", {
	Size = UDim2.new(1, -8, 1, -8),
	Position = UDim2.new(0, 4, 0, 4),
	BackgroundColor3 = C_PANEL,
	BorderSizePixel = 0,
	AutoButtonColor = false,
	Text = "EQUIP / TOGGLE",
	Font = Enum.Font.Arcade,
	TextSize = 16,
	TextColor3 = C_YEL,
}, equipBtnOuter)

-- middle: grid
local gridWrap = mk("Frame", {
	Name = "GridWrap",
	BackgroundTransparency = 1,
	Position = UDim2.new(0, 250, 0, 80),
	Size = UDim2.new(1, -(250 + 260 + 36), 1, -98),
}, inner)

local gridOuter = mk("Frame", {
	Name = "GridOuter",
	BackgroundColor3 = C_WHITE,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1,1),
}, gridWrap)

local gridPanel = mk("Frame", {
	Name = "GridPanel",
	BackgroundColor3 = C_PANEL2,
	BorderSizePixel = 0,
	Position = UDim2.new(0, 4, 0, 4),
	Size = UDim2.new(1, -8, 1, -8),
}, gridOuter)

local scroll = mk("ScrollingFrame", {
	Name = "Scroll",
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Size = UDim2.new(1, -14, 1, -14),
	Position = UDim2.new(0, 7, 0, 7),
	ScrollBarThickness = 8,
	CanvasSize = UDim2.new(0,0,0,0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, gridPanel)

mk("UIGridLayout", {
	CellSize = UDim2.new(0, 150, 0, 150),
	CellPadding = UDim2.new(0, 12, 0, 12),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, scroll)

-- ====== TAB BUTTON CREATION ======
local function makeTab(name, order)
	local outer = mk("Frame", {
		BackgroundColor3 = C_WHITE,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 54),
		LayoutOrder = order,
	}, tabs)

	local innerB = mk("TextButton", {
		BackgroundColor3 = C_PANEL2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 4, 0, 4),
		Size = UDim2.new(1, -8, 1, -8),
		AutoButtonColor = false,
		Text = name:upper(),
		Font = Enum.Font.Arcade,
		TextSize = 16,
		TextColor3 = Color3.fromRGB(220,220,230),
	}, outer)

	return innerB, outer
end

local tabDefs = {
	{key="Weapon", label="Weapons"},
	{key="Armor",  label="Armour"},
	{key="Rune",   label="Runes"},
	{key="Misc",   label="Other"},
}

local tabsUI = {}
for i, tdef in ipairs(tabDefs) do
	local b, outer = makeTab(tdef.label, i)
	tabsUI[tdef.key] = {btn=b, outer=outer}
end

local activeType = "Weapon"
local function setTabActive(typeKey)
	activeType = typeKey
	for k, ui in pairs(tabsUI) do
		local on = (k == activeType)
		ui.outer.BackgroundColor3 = on and C_YEL or C_WHITE
		ui.btn.TextColor3 = on and C_YEL or Color3.fromRGB(220,220,230)
	end
end

-- ====== ITEM CARD ======
local function makeCard(parent)
	local outer = mk("Frame", {
		BackgroundColor3 = C_WHITE,
		BorderSizePixel = 0,
	}, parent)

	local card = mk("TextButton", {
		BackgroundColor3 = C_PANEL,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Size = UDim2.fromScale(1,1),
		Position = UDim2.new(0,4,0,4),
	}, outer)

	outer.Size = UDim2.new(0, 150, 0, 150) -- grid controls actual layout; safe default

	local icon = mk("ImageLabel", {
		Name = "Icon",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.new(0, 64, 0, 64),
		Image = "",
		ImageTransparency = 0.05,
	}, card)

	local name = mk("TextLabel", {
		Name = "Name",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(1, -16, 0, 22),
		Text = "ITEM",
		Font = Enum.Font.Arcade,
		TextSize = 14,
		TextColor3 = C_WHITE,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}, card)

	local rarity = mk("TextLabel", {
		Name = "Rarity",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -36),
		Size = UDim2.new(1, -16, 0, 16),
		Text = "COMMON",
		Font = Enum.Font.Code,
		TextSize = 12,
		TextColor3 = C_MUTE,
	}, card)

	local eq = mk("TextLabel", {
		Name = "Equipped",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 12, 0, 10),
		Size = UDim2.new(1, -24, 0, 16),
		Text = "",
		Font = Enum.Font.Arcade,
		TextSize = 12,
		TextColor3 = C_ACC2,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)

	return outer, card, icon, name, rarity, eq
end

-- ====== STATE ======
local open = false
local data = { items = {} }

local selectedId = nil
local itemsById = {}
local cards = {}

local function clearGrid()
	for _, c in ipairs(cards) do
		if c and c.Parent then c:Destroy() end
	end
	table.clear(cards)
end

local function resetDetails()
	selectedId = nil
	detTitle.Text = "SELECT AN ITEM"
	detInfo.Text = "Pick something.\nPreferably something dangerous."
	equipBtn.Text = "EQUIP / TOGGLE"
end

local function render()
	clearGrid()

	local items = data.items or {}

	itemsById = {}
	for _, it in ipairs(items) do
		if it.itemId then itemsById[it.itemId] = it end
	end

	local count = 0
	for _, item in ipairs(items) do
		local attrs = item.attrs or {}
		local itType = tostring(attrs.ItemType or "Misc")
		local rar = tostring(attrs.Rarity or "Common")
		local iconId = tostring(attrs.Icon or "")

		if itType == activeType then
			count += 1
			local outer, card, icon, name, rarLbl, eq = makeCard(scroll)
			table.insert(cards, outer)

			name.Text = item.name or "???"
			rarLbl.Text = string.upper(rar)
			rarLbl.TextColor3 = rarityColor(rar)
			outer.BackgroundColor3 = rarityColor(rar)

			if iconId ~= "" then
				icon.Image = iconId
				icon.ImageTransparency = 0.05
			else
				icon.Image = ""
				icon.ImageTransparency = 1
			end

			eq.Text = item.equipped and "EQUIPPED" or ""

			card.MouseButton1Click:Connect(function()
				selectedId = item.itemId
				detTitle.Text = item.name or "ITEM"

				local desc = tostring(attrs.Description or "")
				if desc == "" then
					desc = "No description. Which somehow makes it more threatening."
				end

				detInfo.Text = ("%s\n\nRarity: %s\nType: %s"):format(desc, rar, itType)

				local isEq = item.equipped == true
				equipBtn.Text = isEq and "UNEQUIP" or "EQUIP"
			end)
		end
	end

	if count == 0 then
		local empty = mk("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, 60),
			Text = "EMPTY.\nGO GET SOMETHING THAT DOES DAMAGE.",
			Font = Enum.Font.Arcade,
			TextSize = 18,
			TextColor3 = C_MUTE,
			TextYAlignment = Enum.TextYAlignment.Center,
		}, scroll)
		table.insert(cards, empty)
	end
end

-- ====== OPEN/CLOSE ======
local function setOpen(state)
	if combatOpen then
		-- Combat UI is open; inventory stays hidden.
		open = false
		window.Visible = false
		return
	end

	open = state
	window.Visible = open

	if open then
		window.Size = UDim2.new(0, 860, 0, 520)
		TweenService:Create(window, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, 920, 0, 560)
		}):Play()

		local ok, snap = pcall(function()
			return InventoryRF:InvokeServer("Get")
		end)
		if ok and snap then data = snap end
		resetDetails()
		render()
	end
end

openBtn.MouseButton1Click:Connect(function()
	setOpen(not open)
end)

close.MouseButton1Click:Connect(function()
	setOpen(false)
end)

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if combatOpen then return end

	if input.KeyCode == Enum.KeyCode.B then
		setOpen(not open)
	end
	if input.KeyCode == Enum.KeyCode.Escape and open then
		setOpen(false)
	end
end)

-- ====== Tabs ======
for _, tdef in ipairs(tabDefs) do
	local typeKey = tdef.key
	tabsUI[typeKey].btn.MouseButton1Click:Connect(function()
		setTabActive(typeKey)
		resetDetails()
		render()
	end)
end
setTabActive(activeType)

-- ====== Equip button (itemId) ======
equipBtn.MouseButton1Click:Connect(function()
	if combatOpen then return end
	if not selectedId then return end

	local before = itemsById[selectedId]
	local wasEquipped = before and before.equipped == true

	local ok, res = pcall(function()
		return InventoryRF:InvokeServer("Equip", { itemId = selectedId })
	end)
	if not ok then
		warn("Equip invoke failed:", res)
	end

	local ok2, snap = pcall(function()
		return InventoryRF:InvokeServer("Get")
	end)
	if ok2 and snap then
		data = snap
	end

	if wasEquipped then
		HUDSignal:Fire({ type = "RemoveFromHUD", itemId = selectedId })
	end

	resetDetails()
	render()
end)

-- ====== Server pushes updates ======
InventoryRE.OnClientEvent:Connect(function(snap)
	if typeof(snap) ~= "table" then return end

	if snap.type and snap.payload then
		if snap.type == "Snapshot" then
			data = snap.payload or data
		elseif snap.type == "Upsert" then
			local pkt = snap.payload
			if pkt and pkt.itemId then
				data.items = data.items or {}
				local replaced = false
				for i, it in ipairs(data.items) do
					if it.itemId == pkt.itemId then
						data.items[i] = pkt
						replaced = true
						break
					end
				end
				if not replaced then
					table.insert(data.items, pkt)
				end
			end
		elseif snap.type == "Remove" then
			local p = snap.payload
			if p and p.itemId and data.items then
				for i = #data.items, 1, -1 do
					if data.items[i].itemId == p.itemId then
						table.remove(data.items, i)
					end
				end
			end
		elseif snap.type == "EquipState" then
			data = snap.payload or data
		end
	else
		data = snap
	end

	if open and not combatOpen then
		render()
	end
end)

-- ====== Combat bridge: hide inventory when fight menu opens ======
task.spawn(function()
	local cb = getCombatBridge()
	if cb and cb.Event then
		cb.Event:Connect(function(kind)
			if kind == "Open" then
				setCombatOpen(true)
				-- hard hide inventory UI bits
				open = false
				window.Visible = false
				openBtn.Visible = false
				overlay.Visible = false
			elseif kind == "Close" then
				setCombatOpen(false)
				openBtn.Visible = true
				overlay.Visible = true
			end
		end)
	end
end)

-- ====== Visual loop ======
local t = 0
RunService.RenderStepped:Connect(function(dt)
	if combatOpen then return end
	t += dt
	scanGrad.Offset = Vector2.new(0, (t * 0.22) % 1)
	noiseGrad.Offset = Vector2.new(math.sin(t*0.8)*0.12, math.cos(t*0.9)*0.12)
end)

resetDetails()
print("[InventoryUI] Loaded (auto-hides during Combat UI).")
