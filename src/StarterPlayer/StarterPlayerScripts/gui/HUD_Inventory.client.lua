-- StarterPlayerScripts/HUD_Inventory.client.lua
-- Sticky 6-slot HUD (hardened) + FULL VFX OVERHAUL (NO ROUNDED EDGES)
-- ✅ Forces CoreGui Backpack OFF (anti-reenable)
-- ✅ 1-6 handled via ContextActionService at high priority
-- ✅ Robust respawn rehook + tool scanning
-- ✅ Tool stays in slot; slot clears ONLY via HUDInventorySignal RemoveFromHUD
-- ✅ Equipped glow when in Character (NOW: multi-layer pro glow + corner brackets)
-- ✅ No blur
-- ✅ Auto-hides whenever Combat UI opens (via __CombatUIBridge)
-- ✅ VISUALS: CRT scanlines/noise/vignette/chromatic split/glitch ticks/shimmer seams
-- ❌ NO UICorner anywhere (sharp/pixel look only)

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer

-- =========================
-- HARD: Keep Roblox Backpack hidden
-- =========================
local function setCoreSafe(t, enabled)
	pcall(function() StarterGui:SetCoreGuiEnabled(t, enabled) end)
end

setCoreSafe(Enum.CoreGuiType.Health, false)
setCoreSafe(Enum.CoreGuiType.Backpack, false)

local coreHeartbeatConn
coreHeartbeatConn = RunService.Heartbeat:Connect(function()
	if not player.Parent then
		if coreHeartbeatConn then coreHeartbeatConn:Disconnect() end
		return
	end
	setCoreSafe(Enum.CoreGuiType.Backpack, false)
	setCoreSafe(Enum.CoreGuiType.Health, false)
end)

-- =========================
-- Helpers
-- =========================
local function mk(t, props, parent)
	local o = Instance.new(t)
	for k, v in pairs(props or {}) do o[k] = v end
	o.Parent = parent
	return o
end

local function clamp01(x) return math.clamp(x, 0, 1) end

local function waitForHumanoid(timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 10) do
		local char = player.Character
		if char then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then return hum end
		end
		task.wait(0.05)
	end
	return nil
end

local function waitForBackpack(timeout)
	local t0 = os.clock()
	while os.clock() - t0 < (timeout or 10) do
		local bp = player:FindFirstChildOfClass("Backpack")
		if bp then return bp end
		task.wait(0.05)
	end
	return nil
end

-- =========================
-- NO BLUR
-- =========================
for _, fx in ipairs(Lighting:GetChildren()) do
	if fx:IsA("BlurEffect") then
		fx.Enabled = false
		fx.Size = 0
	end
end

-- =========================
-- Shared local signal (client-only)
-- =========================
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

-- =========================
-- COMBAT BRIDGE (hide HUD when combat opens)
-- =========================
local function getCombatBridge()
	local pg = player:WaitForChild("PlayerGui")
	local ev = pg:FindFirstChild("__CombatUIBridge")
	if not ev then
		ev = pg:WaitForChild("__CombatUIBridge", 10)
	end
	return ev
end

local combatOpen = false

-- =========================
-- THEME (sharper, higher contrast, expensive glow stacks)
-- =========================
local C_BG        = Color3.fromRGB(6, 6, 8)
local C_PANEL     = Color3.fromRGB(12, 12, 16)
local C_PANEL2    = Color3.fromRGB(18, 18, 24)
local C_INSET     = Color3.fromRGB(2, 2, 3)

local C_WHITE     = Color3.fromRGB(245, 245, 245)
local C_MUTED     = Color3.fromRGB(165, 165, 175)
local C_DIM       = Color3.fromRGB(95, 95, 110)

local C_ACCENT    = Color3.fromRGB(170, 255, 210) -- your equipped glow hue
local C_ACCENT2   = Color3.fromRGB(70, 210, 160)

local C_HP1       = Color3.fromRGB(255, 70, 70)
local C_HP2       = Color3.fromRGB(190, 25, 25)

local C_ST1       = Color3.fromRGB(120, 255, 170)
local C_ST2       = Color3.fromRGB(30, 120, 70)

-- Pixel/CRT VFX intensity knobs
local VFX = {
	ScanAlpha = 0.12,
	NoiseAlpha = 0.08,
	VignetteAlpha = 0.22,
	ChromaticAlpha = 0.08,
	GlitchTickChance = 0.020, -- per frame chance while enabled
	GlitchMaxShift = 2,       -- px
	SheenStrength = 0.85,     -- slot sheen
}

-- =========================
-- GUI ROOT
-- =========================
local pg = player:WaitForChild("PlayerGui")
local existingGui = pg:FindFirstChild("OverkillHUD")
if existingGui then existingGui:Destroy() end

local gui = mk("ScreenGui", {
	Name = "OverkillHUD",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 2000,
}, pg)

-- =========================
-- Fullscreen post-style overlay stack (NO blur, but CRT vibes)
-- =========================
local overlay = mk("Frame", {
	Name="Overlay",
	BackgroundTransparency=1,
	Size=UDim2.fromScale(1,1),
}, gui)

-- Vignette (fake via gradients)
local vignette = mk("Frame", {
	Name="Vignette",
	BackgroundColor3 = Color3.fromRGB(0,0,0),
	BackgroundTransparency = 1 - VFX.VignetteAlpha,
	BorderSizePixel = 0,
	Size = UDim2.fromScale(1,1),
}, overlay)

local vg = mk("UIGradient", {
	Rotation = 0,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(0,0,0)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0,0,0)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(0,0,0)),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.0, 0.0),
		NumberSequenceKeypoint.new(0.12, 0.35),
		NumberSequenceKeypoint.new(0.5, 1.0),
		NumberSequenceKeypoint.new(0.88, 0.35),
		NumberSequenceKeypoint.new(1.0, 0.0),
	}),
	Offset = Vector2.new(0,0),
}, vignette)

-- Scanlines (tight + subtle drift)
local scan = mk("Frame", {
	Name="Scanlines",
	BackgroundColor3 = C_WHITE,
	BackgroundTransparency = 1 - VFX.ScanAlpha,
	BorderSizePixel = 0,
	Size=UDim2.fromScale(1,1),
}, overlay)

local scanGrad = mk("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(C_WHITE, C_WHITE),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.00, 0.90),
		NumberSequenceKeypoint.new(0.48, 0.90),
		NumberSequenceKeypoint.new(0.50, 0.65),
		NumberSequenceKeypoint.new(0.52, 0.90),
		NumberSequenceKeypoint.new(1.00, 0.90),
	}),
	Offset = Vector2.new(0,0),
}, scan)

-- Noise (procedural-ish via gradient wobble)
local noise = mk("Frame", {
	Name="Noise",
	BackgroundColor3=C_WHITE,
	BackgroundTransparency = 1 - VFX.NoiseAlpha,
	BorderSizePixel=0,
	Size=UDim2.fromScale(1,1),
}, overlay)

local noiseGrad = mk("UIGradient", {
	Rotation = 45,
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0.0, Color3.fromRGB(255,255,255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200,200,210)),
		ColorSequenceKeypoint.new(1.0, Color3.fromRGB(255,255,255)),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.0, 0.88),
		NumberSequenceKeypoint.new(0.5, 0.98),
		NumberSequenceKeypoint.new(1.0, 0.88),
	}),
	Offset = Vector2.new(0,0),
}, noise)

-- Chromatic split (fake RGB edge shift with 3 thin layers)
local chroma = mk("Frame", {
	Name="Chromatic",
	BackgroundTransparency = 1,
	Size=UDim2.fromScale(1,1),
}, overlay)

local function mkChromaLayer(name, color, z, alpha)
	local f = mk("Frame", {
		Name=name,
		BackgroundColor3=color,
		BackgroundTransparency = 1 - alpha,
		BorderSizePixel=0,
		Size=UDim2.fromScale(1,1),
		ZIndex = z,
	}, chroma)
	local g = mk("UIGradient", {
		Rotation = 0,
		Color = ColorSequence.new(color, color),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, 0.98),
			NumberSequenceKeypoint.new(0.2, 0.92),
			NumberSequenceKeypoint.new(0.5, 0.88),
			NumberSequenceKeypoint.new(0.8, 0.92),
			NumberSequenceKeypoint.new(1.0, 0.98),
		})
	}, f)
	return f, g
end

local chromaR = mkChromaLayer("R", Color3.fromRGB(255,80,80), 5, VFX.ChromaticAlpha)
local chromaG = mkChromaLayer("G", Color3.fromRGB(90,255,160), 6, VFX.ChromaticAlpha)
local chromaB = mkChromaLayer("B", Color3.fromRGB(110,160,255), 7, VFX.ChromaticAlpha)

-- =========================
-- BOTTOM-CENTER HUD LAYOUT
-- =========================
local root = mk("Frame", {
	Name="BottomHUD",
	BackgroundTransparency=1,
	AnchorPoint=Vector2.new(0.5,1),
	Position=UDim2.new(0.5,0,1,-24),
	Size=UDim2.new(0,860,0,150)
}, gui)

local row = mk("Frame", {Name="Row", BackgroundTransparency=1, Size=UDim2.fromScale(1,1)}, root)
mk("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	VerticalAlignment = Enum.VerticalAlignment.Bottom,
	Padding = UDim.new(0, 14),
	SortOrder = Enum.SortOrder.LayoutOrder
}, row)

-- =========================
-- HOTBAR SLOT CREATION (NO ROUNDING, heavy detail)
-- =========================
local function makeCornerBrackets(parent, color, z)
	-- Four small bracket pieces, pixel sharp
	local b = {}

	local function piece(name, pos, size)
		return mk("Frame", {
			Name = name,
			BackgroundColor3 = color,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			Position = pos,
			Size = size,
			ZIndex = z,
		}, parent)
	end

	local thick = 2
	local len = 14

	-- TL
	b.tl_h = piece("TL_H", UDim2.new(0, 6, 0, 6), UDim2.new(0, len, 0, thick))
	b.tl_v = piece("TL_V", UDim2.new(0, 6, 0, 6), UDim2.new(0, thick, 0, len))

	-- TR
	b.tr_h = piece("TR_H", UDim2.new(1, -(6+len), 0, 6), UDim2.new(0, len, 0, thick))
	b.tr_v = piece("TR_V", UDim2.new(1, -(6+thick), 0, 6), UDim2.new(0, thick, 0, len))

	-- BL
	b.bl_h = piece("BL_H", UDim2.new(0, 6, 1, -(6+thick)), UDim2.new(0, len, 0, thick))
	b.bl_v = piece("BL_V", UDim2.new(0, 6, 1, -(6+len)), UDim2.new(0, thick, 0, len))

	-- BR
	b.br_h = piece("BR_H", UDim2.new(1, -(6+len), 1, -(6+thick)), UDim2.new(0, len, 0, thick))
	b.br_v = piece("BR_V", UDim2.new(1, -(6+thick), 1, -(6+len)), UDim2.new(0, thick, 0, len))

	return b
end

local function makeSlot(parent, index)
	local slot = mk("TextButton", {
		Name = ("Slot%d"):format(index),
		BackgroundColor3 = C_PANEL,
		BackgroundTransparency = 0.04,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 92, 0, 92),
		AutoButtonColor = false,
		Text = "",
		LayoutOrder = index,
		Visible = true,
	}, parent)

	-- Inner inset (gives depth)
	local inset = mk("Frame", {
		Name = "Inset",
		BackgroundColor3 = C_INSET,
		BackgroundTransparency = 0.0,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 3, 0, 3),
		Size = UDim2.new(1, -6, 1, -6),
		ZIndex = 2,
	}, slot)

	-- Main stroke (base)
	local stroke = mk("UIStroke", {
		Thickness = 2,
		Transparency = 0.70,
		Color = C_WHITE,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, slot)

	-- Secondary stroke (inner, dim) for “manufactured” look
	local stroke2 = mk("UIStroke", {
		Thickness = 1,
		Transparency = 0.82,
		Color = C_DIM,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, inset)

	-- Slot index label (sharp)
	mk("TextLabel", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 0, 8),
		Size = UDim2.new(0, 30, 0, 18),
		Text = tostring(index),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextColor3 = C_WHITE,
		TextTransparency = 0.08,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 20,
	}, slot)

	-- Tool name
	local name = mk("TextLabel", {
		Name = "ToolName",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -10),
		Size = UDim2.new(1, -18, 0, 18),
		Text = "EMPTY",
		Font = Enum.Font.GothamSemibold,
		TextSize = 12,
		TextColor3 = C_MUTED,
		TextTransparency = 0.06,
		TextTruncate = Enum.TextTruncate.AtEnd,
		ZIndex = 20,
	}, slot)

	-- Corner brackets (expensive “HUD” vibe)
	local brackets = makeCornerBrackets(slot, C_DIM, 25)

	-- Sheen layer (animated gradient sweep)
	local sheen = mk("Frame", {
		Name = "Sheen",
		BackgroundColor3 = C_WHITE,
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(1.15, 0, 1.15, 0),
		Rotation = -12,
		ZIndex = 10,
	}, slot)

	local sheenGrad = mk("UIGradient", {
		Rotation = 0,
		Color = ColorSequence.new(C_WHITE, C_WHITE),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, 1.0),
			NumberSequenceKeypoint.new(0.35, 0.90),
			NumberSequenceKeypoint.new(0.50, 0.78),
			NumberSequenceKeypoint.new(0.65, 0.90),
			NumberSequenceKeypoint.new(1.0, 1.0),
		}),
		Offset = Vector2.new(-0.6, 0),
	}, sheen)

	-- “Energy seam” strip (thin moving highlight)
	local seam = mk("Frame", {
		Name="Seam",
		BackgroundColor3 = C_WHITE,
		BackgroundTransparency = 0.92,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 1),
		ZIndex = 30,
	}, inset)
	local seamGrad = mk("UIGradient", {
		Rotation = 0,
		Color = ColorSequence.new(C_WHITE, C_WHITE),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0.0, 1.0),
			NumberSequenceKeypoint.new(0.45, 0.60),
			NumberSequenceKeypoint.new(0.50, 0.15),
			NumberSequenceKeypoint.new(0.55, 0.60),
			NumberSequenceKeypoint.new(1.0, 1.0),
		}),
		Offset = Vector2.new(-0.4, 0),
	}, seam)

	-- Glow stack (equipped)
	local glow = mk("UIStroke", {
		Name = "Glow",
		Thickness = 2,
		Transparency = 1,
		Color = C_ACCENT,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, slot)

	-- Outer bloom (second stroke)
	local bloom = mk("UIStroke", {
		Name = "Bloom",
		Thickness = 5,
		Transparency = 1,
		Color = C_ACCENT2,
		LineJoinMode = Enum.LineJoinMode.Miter,
	}, slot)

	-- Keep references stable for the existing logic + render loop
	slot:SetAttribute("__HasVFXOverhaul", true)

	return slot, stroke, sheenGrad, glow, name, {
		brackets = brackets,
		stroke2 = stroke2,
		seamGrad = seamGrad,
		bloom = bloom,
		inset = inset,
	}
end

local left = mk("Frame", {Name="LeftSlots", BackgroundTransparency=1, Size=UDim2.new(0,310,0,110), LayoutOrder=1}, row)
mk("UIListLayout", {FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0,10), HorizontalAlignment=Enum.HorizontalAlignment.Center, VerticalAlignment=Enum.VerticalAlignment.Bottom}, left)

local core = mk("Frame", {Name="Core", BackgroundTransparency=1, Size=UDim2.new(0,210,0,140), LayoutOrder=2}, row)

local right = mk("Frame", {Name="RightSlots", BackgroundTransparency=1, Size=UDim2.new(0,310,0,110), LayoutOrder=3}, row)
mk("UIListLayout", {FillDirection=Enum.FillDirection.Horizontal, Padding=UDim.new(0,10), HorizontalAlignment=Enum.HorizontalAlignment.Center, VerticalAlignment=Enum.VerticalAlignment.Bottom}, right)

local slots = {}
for i=1,3 do
	local s, stroke, sheenGrad, glow, name, extra = makeSlot(left, i)
	slots[i] = {btn=s, stroke=stroke, sheen=sheenGrad, glow=glow, label=name, itemId=nil, extra=extra}
end
for i=4,6 do
	local s, stroke, sheenGrad, glow, name, extra = makeSlot(right, i)
	slots[i] = {btn=s, stroke=stroke, sheen=sheenGrad, glow=glow, label=name, itemId=nil, extra=extra}
end

-- =========================
-- CORE HP/ST (NO ROUNDING, more “instrument panel”)
-- =========================
local corePanel = mk("Frame", {
	BackgroundColor3 = C_BG,
	BackgroundTransparency = 0.08,
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 0),
	Size = UDim2.new(0, 210, 0, 140),
}, core)

mk("UIStroke", {Thickness = 2, Transparency = 0.58, Color = C_WHITE, LineJoinMode = Enum.LineJoinMode.Miter}, corePanel)

-- Panel detail: top “header” strip + micro ticks
local header = mk("Frame", {
	Name="Header",
	BackgroundColor3 = C_PANEL2,
	BackgroundTransparency = 0.05,
	BorderSizePixel=0,
	Position = UDim2.new(0, 2, 0, 2),
	Size = UDim2.new(1, -4, 0, 20),
}, corePanel)

mk("UIStroke", {Thickness=1, Transparency=0.80, Color=C_DIM, LineJoinMode=Enum.LineJoinMode.Miter}, header)

mk("TextLabel", {
	BackgroundTransparency=1,
	Position = UDim2.new(0, 10, 0, 2),
	Size = UDim2.new(1, -20, 1, -4),
	Text = "STATUS",
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = C_MUTED,
	TextTransparency = 0.10,
	TextXAlignment = Enum.TextXAlignment.Left,
}, header)

local hpBack = mk("Frame", {
	BackgroundColor3 = Color3.fromRGB(24,24,30),
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -18),
	Size = UDim2.new(0, 180, 0, 12),
}, corePanel)
mk("UIStroke", {Thickness=1, Transparency=0.78, Color=C_DIM, LineJoinMode=Enum.LineJoinMode.Miter}, hpBack)

local hpFill = mk("Frame", {BackgroundColor3=C_HP1, BorderSizePixel=0, Size=UDim2.new(1,0,1,0)}, hpBack)
mk("UIGradient", {Color=ColorSequence.new(C_HP1, C_HP2)}, hpFill)

-- HP “specular” line
local hpSpec = mk("Frame", {
	BackgroundColor3 = C_WHITE,
	BackgroundTransparency = 0.90,
	BorderSizePixel=0,
	Position = UDim2.new(0, 0, 0, 1),
	Size = UDim2.new(1, 0, 0, 1),
}, hpFill)
local hpSpecGrad = mk("UIGradient", {
	Rotation = 0,
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0.0, 1.0),
		NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1.0, 1.0),
	}),
}, hpSpec)

local hpText = mk("TextLabel", {
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -32),
	Size = UDim2.new(0, 180, 0, 16),
	Text = "HP 0 / 0",
	Font = Enum.Font.GothamBold,
	TextSize = 13,
	TextColor3 = C_WHITE,
	TextTransparency = 0.06,
}, corePanel)

local stBack = mk("Frame", {
	BackgroundColor3 = Color3.fromRGB(24,24,30),
	BorderSizePixel = 0,
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -2),
	Size = UDim2.new(0, 180, 0, 10),
}, corePanel)
mk("UIStroke", {Thickness=1, Transparency=0.78, Color=C_DIM, LineJoinMode=Enum.LineJoinMode.Miter}, stBack)

local stFill = mk("Frame", {BackgroundColor3=C_ST1, BorderSizePixel=0, Size=UDim2.new(1,0,1,0)}, stBack)
local stGrad = mk("UIGradient", {Color=ColorSequence.new(C_ST1, C_ST2)}, stFill)

-- =========================
-- TOOL / SLOT LOGIC (UNCHANGED)
-- =========================
local function getBackpack()
	return player:FindFirstChildOfClass("Backpack")
end

local function getHumanoid()
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid") or nil
end

local function findToolByItemId(itemId)
	local char = player.Character
	local bp = getBackpack()

	local function scan(container)
		if not container then return nil end
		for _, inst in ipairs(container:GetChildren()) do
			if inst:IsA("Tool") and inst:GetAttribute("ItemId") == itemId then
				return inst
			end
		end
		return nil
	end

	return scan(char) or scan(bp)
end

local function isEquipped(tool)
	local char = player.Character
	return tool and char and tool.Parent == char
end

local function slotIndexByItemId(itemId)
	for i=1,6 do
		if slots[i].itemId == itemId then return i end
	end
	return nil
end

local function firstEmptySlot()
	for i=1,6 do
		if slots[i].itemId == nil then return i end
	end
	return nil
end

local function setSlotVisual(i)
	local s = slots[i]
	local ex = s.extra

	if not s.itemId then
		s.label.Text = "EMPTY"
		s.label.TextColor3 = C_MUTED
		s.stroke.Transparency = 0.78
		ex.stroke2.Transparency = 0.86
		ex.bloom.Transparency = 1
		s.glow.Transparency = 1
		s.btn.BackgroundTransparency = 0.06

		-- brackets dim
		for _,p in pairs(ex.brackets) do p.BackgroundColor3 = C_DIM; p.BackgroundTransparency = 0.10 end
		return
	end

	local tool = findToolByItemId(s.itemId)
	if not tool then
		s.itemId = nil
		s.label.Text = "EMPTY"
		s.label.TextColor3 = C_MUTED
		s.stroke.Transparency = 0.78
		ex.stroke2.Transparency = 0.86
		ex.bloom.Transparency = 1
		s.glow.Transparency = 1
		s.btn.BackgroundTransparency = 0.06
		for _,p in pairs(ex.brackets) do p.BackgroundColor3 = C_DIM; p.BackgroundTransparency = 0.10 end
		return
	end

	s.label.Text = tool.Name
	local eq = isEquipped(tool)

	s.label.TextColor3 = eq and C_WHITE or C_MUTED
	s.stroke.Transparency = eq and 0.28 or 0.72
	ex.stroke2.Transparency = eq and 0.70 or 0.86

	-- Equipped glow stack
	s.glow.Transparency = eq and 0.18 or 1
	ex.bloom.Transparency = eq and 0.72 or 1

	-- background “pressure”
	s.btn.BackgroundTransparency = eq and 0.02 or 0.06

	-- brackets
	for _,p in pairs(ex.brackets) do
		p.BackgroundColor3 = eq and C_ACCENT or C_DIM
		p.BackgroundTransparency = eq and 0.00 or 0.10
	end
end

local function refreshSlots()
	for i=1,6 do setSlotVisual(i) end
end

local function tryAutoAssign(tool)
	if not tool:IsA("Tool") then return end
	local itemId = tool:GetAttribute("ItemId")
	if typeof(itemId) ~= "string" or itemId == "" then return end
	if slotIndexByItemId(itemId) then return end
	local empty = firstEmptySlot()
	if empty then
		slots[empty].itemId = itemId
	end
end

local function toggleEquipForSlot(i)
	if combatOpen then return end
	local s = slots[i]
	if not s.itemId then return end

	local tool = findToolByItemId(s.itemId)
	if not tool then return end

	local hum = getHumanoid()
	if not hum then return end

	if isEquipped(tool) then
		hum:UnequipTools()
	else
		hum:EquipTool(tool)
	end

	task.delay(0.05, refreshSlots)
end

for i=1,6 do
	slots[i].btn.MouseButton1Click:Connect(function()
		toggleEquipForSlot(i)
	end)
end

-- =========================
-- INPUT: HIGH PRIORITY 1-6
-- =========================
local keyToSlot = {
	[Enum.KeyCode.One]=1,[Enum.KeyCode.Two]=2,[Enum.KeyCode.Three]=3,
	[Enum.KeyCode.Four]=4,[Enum.KeyCode.Five]=5,[Enum.KeyCode.Six]=6,
}

local function hotbarAction(actionName, inputState, inputObject)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if combatOpen then
		return Enum.ContextActionResult.Sink
	end
	local idx = keyToSlot[inputObject.KeyCode]
	if idx then
		toggleEquipForSlot(idx)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function bindHotkeys()
	ContextActionService:UnbindAction("__HUD_HOTBAR__")
	ContextActionService:BindActionAtPriority(
		"__HUD_HOTBAR__",
		hotbarAction,
		false,
		99950,
		Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three,
		Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six
	)
end
bindHotkeys()

-- =========================
-- Inventory UI can explicitly remove from HUD
-- =========================
HUDSignal.Event:Connect(function(msg)
	if typeof(msg) ~= "table" then return end
	if msg.type == "RemoveFromHUD" and typeof(msg.itemId) == "string" then
		local idx = slotIndexByItemId(msg.itemId)
		if idx then
			slots[idx].itemId = nil
			refreshSlots()
		end
	end
end)

-- =========================
-- Container hooks (robust)
-- =========================
local bpConns = {}
local function clearConns()
	for _, c in ipairs(bpConns) do
		if c then c:Disconnect() end
	end
	bpConns = {}
end

local function hookContainers()
	clearConns()

	local bp = getBackpack()
	if bp then
		table.insert(bpConns, bp.ChildAdded:Connect(function(child)
			tryAutoAssign(child)
			task.defer(refreshSlots)
		end))
		table.insert(bpConns, bp.ChildRemoved:Connect(function()
			task.defer(refreshSlots)
		end))
	end

	local char = player.Character
	if char then
		table.insert(bpConns, char.ChildAdded:Connect(function(child)
			tryAutoAssign(child)
			task.defer(refreshSlots)
		end))
		table.insert(bpConns, char.ChildRemoved:Connect(function()
			task.defer(refreshSlots)
		end))
	end
end

local function initialScan()
	local bp = getBackpack()
	if bp then for _, t in ipairs(bp:GetChildren()) do tryAutoAssign(t) end end
	local char = player.Character
	if char then for _, t in ipairs(char:GetChildren()) do tryAutoAssign(t) end end
	refreshSlots()
end

player.CharacterAdded:Connect(function()
	bindHotkeys()
	task.delay(0.15, function()
		hookContainers()
		initialScan()
	end)
end)

task.spawn(function()
	waitForBackpack(10)
	waitForHumanoid(10)
	hookContainers()
	initialScan()
end)

-- =========================
-- Combat bridge listener
-- =========================
task.spawn(function()
	local cb = getCombatBridge()
	if cb and cb.Event then
		cb.Event:Connect(function(kind)
			if kind == "Open" then
				combatOpen = true
				gui.Enabled = false
			elseif kind == "Close" then
				combatOpen = false
				gui.Enabled = true
			end
		end)
	end
end)

-- =========================
-- Render loop (visuals + stats) (logic unchanged, visuals upgraded)
-- =========================
local t = 0
local lastHP, lastST = 1, 1
local function setBar(fill, a) fill.Size = UDim2.new(clamp01(a), 0, 1, 0) end

RunService.RenderStepped:Connect(function(dt)
	if combatOpen or not gui.Enabled then return end
	t += dt

	-- CRT drift
	scanGrad.Offset = Vector2.new(0, (t * 0.28) % 1)
	noiseGrad.Offset = Vector2.new(math.sin(t*0.92)*0.14, math.cos(t*0.83)*0.14)

	-- Chromatic micro-shift (subtle)
	local cx = math.sin(t*1.9) * 0.0015
	local cy = math.cos(t*1.6) * 0.0010
	chromaR.Position = UDim2.new(cx, -1, cy, 0)
	chromaG.Position = UDim2.new(-cx, 0, -cy, 0)
	chromaB.Position = UDim2.new(cx*0.5, 1, -cy*0.5, 0)

	-- Occasional glitch tick (tiny and mean, not obnoxious)
	if math.random() < VFX.GlitchTickChance then
		local shift = math.random(-VFX.GlitchMaxShift, VFX.GlitchMaxShift)
		local bandY = math.random(0, 100) / 100
		local bandH = math.random(10, 22)

		scan.Position = UDim2.new(0, shift, 0, 0)
		noise.Position = UDim2.new(0, -shift, 0, 0)

		-- quick “slice” effect by temporarily biasing vignette gradient
		vg.Offset = Vector2.new(math.random(-10,10)/100, bandY)
		task.delay(0.04, function()
			if gui and gui.Parent and gui.Enabled then
				scan.Position = UDim2.new(0,0,0,0)
				noise.Position = UDim2.new(0,0,0,0)
				vg.Offset = Vector2.new(0,0)
			end
		end)
	end

	-- Slot sheen + micro jitter (your existing vibe, but cleaner and layered)
	for i=1,6 do
		local s = slots[i]
		local off = ((t * 0.62) + i*0.11) % 1
		s.sheen.Offset = Vector2.new(off - 0.5, 0)

		local jx = math.sin(t*7 + i) * 0.30
		local jy = math.cos(t*6 + i*2) * 0.22
		s.btn.Position = UDim2.new(0, jx, 0, jy)

		-- Energy seam runs faster when equipped
		local eq = false
		if s.itemId then
			local tool = findToolByItemId(s.itemId)
			eq = isEquipped(tool)
		end
		local seamSpeed = eq and 1.8 or 1.0
		s.extra.seamGrad.Offset = Vector2.new(((t*seamSpeed) + i*0.2) % 1 - 0.5, 0)
	end

	-- HP
	local char = player.Character
	if not char then return end

	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then
		local hp = hum.Health
		local mhp = math.max(1, hum.MaxHealth)
		local a = hp / mhp
		if math.abs(a - lastHP) > 0.002 then
			lastHP = a
			setBar(hpFill, a)
			hpText.Text = ("HP  %d / %d"):format(math.floor(hp + 0.5), math.floor(mhp + 0.5))
		end
		-- subtle spec line shimmer
		hpSpecGrad.Offset = Vector2.new(((t*0.9) % 1) - 0.5, 0)
	end

	-- ST
	local st = char:GetAttribute("Stamina")
	local mst = char:GetAttribute("MaxStamina")
	if st and mst and mst > 0 then
		local a = st / mst
		if math.abs(a - lastST) > 0.002 then
			lastST = a
			setBar(stFill, a)
			if a <= 0.2 then
				stGrad.Rotation = 30 + math.sin(t*6)*10
				stFill.BackgroundTransparency = 0.02 + math.abs(math.sin(t*4))*0.10
			else
				stGrad.Rotation = 0
				stFill.BackgroundTransparency = 0
			end
		end
	end

	-- Keep your periodic refresh behavior (unchanged intent)
	if math.floor(t*10) % 10 == 0 then
		refreshSlots()
	end
end)

print("[OverkillHUD] Loaded (VFX OVERHAUL, NO ROUNDED EDGES, auto-hides during Combat UI).")
