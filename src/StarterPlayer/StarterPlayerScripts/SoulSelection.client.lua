-- StarterPlayerScripts/SoulSelect.client.lua
-- Soul selection screen (FULLSCREEN, cinematic, pixel hearts) - VISUAL REVAMP, LOGIC PRESERVED
-- FINAL POLISH+ (AMENDED):
-- ✅ FIX: "Select" now actually triggers phase 2 via bridge events (Chosen + Mode)
-- ✅ Added: Forced reassignment "ERROR" sequence (reject -> glitch -> force different soul)
-- ✅ Keeps your ring/inspect behavior and visuals
-- ✅ Does NOT change server pipeline. StartMenu still owns slot picker + spawning.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")


local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

math.randomseed(tick() * 100000)

local BRIDGE_NAME = "__SoulSelectBridge"
local bridge = playerGui:WaitForChild(BRIDGE_NAME)

-- =========================
-- StartMenu integration (SOUL persistence pipeline)
-- We CANNOT call MenuAction:SetSoul here because we don't know reqId/slot yet.
-- So we store a pending soul choice and let the StartMenu client send SetSoul
-- at the correct time (it knows reqId + slot).
-- =========================
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local MenuAction = Remotes:WaitForChild("MenuAction")

local function setPendingSoul(key: string)
	key = tostring(key or "")
	if key == "" then return end

	-- Immediate local + replicated value (useful for BulletHell checks etc.)
	player:SetAttribute("SoulType", key)

	-- Dedicated "pending" key StartMenu UI should read when starting a run
	player:SetAttribute("PendingSoulType", key)
end


-- =========================
-- Soul authority bridge (server sets CurrentSoul attribute)
-- =========================
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local SoulSwitchRE = Remotes:FindFirstChild("SoulSwitchRE") -- created by SoulService on server (recommended)

local function setSoulServer(key: string)
	key = tostring(key or "")
	if key == "" then return end

	-- Prefer server authority if available
	if SoulSwitchRE and SoulSwitchRE:IsA("RemoteEvent") then
		SoulSwitchRE:FireServer(key)
	else
		-- Fallback (client-only): still helps BulletHell3D during early testing
		player:SetAttribute("CurrentSoul", key)
	end
end


local function make(className, props, parent)
	local inst = Instance.new(className)
	for k,v in pairs(props or {}) do inst[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function tween(obj, goal, t, style, dir)
	local ti = TweenInfo.new(t or 0.18, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
	local tw = TweenService:Create(obj, ti, goal)
	tw:Play()
	return tw
end

local function snapPx(px, step)
	step = step or 2
	return math.floor((px / step) + 0.5) * step
end

local function clamp01(x) return math.clamp(x, 0, 1) end
local function lerp(a,b,t) return a + (b-a)*t end
local function easeInOutQuad(t)
	t = clamp01(t)
	if t < 0.5 then
		return 2*t*t
	else
		return 1 - ((-2*t + 2)^2)/2
	end
end

local function addRoughBorder(frame, color, z)
	z = z or (frame.ZIndex + 1)
	local t = 2
	local a = 0.12
	local function edge()
		return make("Frame", {BackgroundColor3=color, BackgroundTransparency=a, BorderSizePixel=0, ZIndex=z, Active=false, Selectable=false}, frame)
	end
	local top = edge()
	local bot = edge()
	local lef = edge()
	local rig = edge()

	top.Size = UDim2.new(1, snapPx(math.random(-8,8)), 0, t)
	top.Position = UDim2.new(0, snapPx(math.random(-2,2)), 0, snapPx(math.random(-2,2)))
	bot.Size = UDim2.new(1, snapPx(math.random(-8,8)), 0, t)
	bot.Position = UDim2.new(0, snapPx(math.random(-2,2)), 1, -t + snapPx(math.random(-2,2)))
	lef.Size = UDim2.new(0, t, 1, snapPx(math.random(-8,8)))
	lef.Position = UDim2.new(0, snapPx(math.random(-2,2)), 0, snapPx(math.random(-2,2)))
	rig.Size = UDim2.new(0, t, 1, snapPx(math.random(-8,8)))
	rig.Position = UDim2.new(1, -t + snapPx(math.random(-2,2)), 0, snapPx(math.random(-2,2)))
end

-- =========================
-- Souls (server-compatible)
-- =========================
local SOULS = {
	{ key="BRAVERY", label="BRAVERY", color=Color3.fromRGB(255,140,40),
		lore={
			"Bravery isn’t a lack of fear.",
			"It’s moving anyway, even when your instincts scream to stop.",
			"Bravery souls don’t negotiate with danger.",
			"They break it, then walk through the pieces."
		},
		passives={"Momentum: chaining hits ramps speed + damage briefly.","First Step: entering combat grants a short shield.","Forward Dodge: dodging into threat builds crit chance."},
		actives={"CHARGE LUNGE: gap-close that breaks guard.","BLOOD DEAL: trade HP for burst damage + lifesteal."},
		drawbacks={"Tunnel Vision: high stacks reduce precision timing.","Blood Price: buffs always cost something."},
	},
	{ key="JUSTICE", label="JUSTICE", color=Color3.fromRGB(255,240,90),
		lore={
			"Justice is a weapon pretending to be a principle.",
			"It doesn’t ask who deserves it.",
			"It asks who’s still standing when the smoke clears."
		},
		passives={"Crit Window: perfect dodge makes next hit crit.","Judgement Mark: repeated damage marks targets for bonus damage.","Clean Angle: ranged attacks pierce partial cover."},
		actives={"DEADEYE: brief focus mode for weak-point burst.","VERDICT: consume marks for a finisher."},
		drawbacks={"Overcommit: missing a key shot opens a punish window.","Cold Focus: supportive output is weaker."},
	},
	{ key="KINDNESS", label="KINDNESS", color=Color3.fromRGB(80,255,140),
		lore={
			"Kindness learns the shape of pain so it can block it.",
			"And once it understands… it can apply it perfectly.",
			"Containment is just a cage with good PR."
		},
		passives={"Guard Aura: near allies/objectives gain damage reduction.","Countercharge: blocking builds a stun pulse.","Stability Field: reduced knockback + stagger time."},
		actives={"BARRIER BLOOM: protective zone + cleanse minor debuffs.","REFLECTIVE EDGE: blocks reflect a portion of damage briefly."},
		drawbacks={"Weight: higher guard reduces movement speed.","Lower burst unless counter-timed."},
	},
	{ key="PATIENCE", label="PATIENCE", color=Color3.fromRGB(90,170,255),
		lore={
			"Patience isn’t waiting. It’s control.",
			"It watches patterns until they confess.",
			"A Patience soul wins fights before they start."
		},
		passives={"Focus Stacks: stay unhit to build accuracy/crit/timing.","Slow Burn: damage ramps over time.","Late Dodge: near-hit dodges cost less stamina."},
		actives={"TIME DILATE: slow enemies/projectiles in an area.","SNARE THREAD: delayed anchor + debuff."},
		drawbacks={"Early dodges cost more stamina.","Taking a hit drops stacks hard."},
	},
	{ key="INTEGRITY", label="INTEGRITY", color=Color3.fromRGB(9,0,136),
		lore={
			"Integrity is shape under pressure.",
			"It isn’t morality. It’s consistency.",
			"It chooses a form and demands the world accept it."
		},
		passives={"Stability: resist debuffs and crowd control.","True Form: after an active, gain defense + stagger immunity.","Anchor: pause briefly to boost next hit stagger + reduce damage."},
		actives={"PURGE: cleanse debuffs + shock ring pushback.","LOCKSTEP: zone that hinders enemies; your attacks gain stagger."},
		drawbacks={"Rigid: slightly lower attack speed.","Stationary timing can be punished."},
	},
	{ key="PERSEVERANCE", label="PERSEVERANCE", color=Color3.fromRGB(157,0,255),
		lore={
			"Perseverance is the refusal to be rewritten.",
			"It’s the voice that says: again.",
			"The world tries to grind you down.",
			"You grind back."
		},
		passives={"Grit: when low HP, gain damage reduction.","Stubborn Core: crowd control durations reduced.","Endure: repeated hits build a temporary shield."},
		actives={"HARD RESET: purge status effects and gain brief immunity.","LAST WORD: short window where damage taken charges a counterburst."},
		drawbacks={"Slow to start: power ramps rather than spikes.","Overheat: strong counters can self-stagger if mistimed."},
	},
}

-- =========================
-- GUI build
-- =========================
local GUI_NAME = "__SoulSelect_RUNTIME"
local old = playerGui:FindFirstChild(GUI_NAME)
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = GUI_NAME
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000000
gui.Enabled = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local root = make("Frame", {
	Size = UDim2.fromScale(1,1),
	BackgroundColor3 = Color3.fromRGB(0,0,0),
	BorderSizePixel = 0,
	Active = false,
}, gui)

local bg = make("Frame", {Size=UDim2.fromScale(1,1), BackgroundColor3=Color3.fromRGB(6,6,10), BorderSizePixel=0, ZIndex=1, Active=false}, root)
make("UIGradient", {Rotation=18, Color=ColorSequence.new(Color3.fromRGB(5,5,8), Color3.fromRGB(18,3,12))}, bg)

-- Background VFX behind everything important
local bgVFX = make("Frame", {
	Size = UDim2.fromScale(1,1),
	BackgroundTransparency = 1,
	ZIndex = 6,
	Active = false,
}, root)

local vfxBlocks = {}
for i=1, 70 do
	local b = make("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = (math.random() < 0.7) and Color3.fromRGB(255,220,140) or Color3.fromRGB(255,60,60),
		BackgroundTransparency = 0.96,
		Size = UDim2.new(0, snapPx(math.random(6,16),2), 0, snapPx(math.random(2,10),2)),
		Position = UDim2.new(math.random(), snapPx(math.random(-80,80),2), math.random(), snapPx(math.random(-80,80),2)),
		ZIndex = 6,
		Active = false,
	}, bgVFX)
	vfxBlocks[i] = {
		gui = b,
		vx = (math.random() * 0.018 + 0.004) * (math.random()<0.5 and -1 or 1),
		vy = (math.random() * 0.018 + 0.004) * (math.random()<0.5 and -1 or 1),
	}
end

local dust = {}
for i=1, 160 do
	local d = make("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(255,255,255),
		BackgroundTransparency = 0.985,
		Size = UDim2.new(0, 1, 0, 1),
		Position = UDim2.new(math.random(), 0, math.random(), 0),
		ZIndex = 6,
		Active = false,
	}, bgVFX)
	dust[i] = {
		gui = d,
		vx = (math.random() * 0.012 + 0.002) * (math.random()<0.5 and -1 or 1),
		vy = (math.random() * 0.012 + 0.002) * (math.random()<0.5 and -1 or 1),
	}
end

local glitchLayer = make("Frame", {Size=UDim2.fromScale(1,1), BackgroundTransparency=1, ZIndex=300, Active=false}, root)
local function glitchBurst(intensity)
	intensity = intensity or 1
	for i=1, math.random(2, 4) do
		local g = make("Frame", {
			BackgroundColor3 = (math.random()<0.5) and Color3.fromRGB(255,220,140) or Color3.fromRGB(255,60,60),
			BackgroundTransparency = 0.82,
			BorderSizePixel=0,
			Size = UDim2.new(math.random(10, 24)/100, 0, 0, snapPx(math.random(8, 16)*intensity,2)),
			Position = UDim2.new(math.random(), snapPx(math.random(-30,30),2), math.random(), snapPx(math.random(-30,30),2)),
			ZIndex = 310,
			Active = false,
		}, glitchLayer)
		task.delay(0.08, function()
			if g and g.Parent then
				tween(g, {BackgroundTransparency=1}, 0.10)
				task.delay(0.12, function() if g and g.Parent then g:Destroy() end end)
			end
		end)
	end
end

make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0, 24, 0, 18),
	Size=UDim2.new(1, -48, 0, 40),
	Text="CHOOSE YOUR SOUL",
	Font=Enum.Font.GothamBlack,
	TextSize=34,
	TextColor3=Color3.fromRGB(245,245,245),
	TextXAlignment=Enum.TextXAlignment.Left,
	ZIndex=40,
}, root)

make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0, 26, 0, 56),
	Size=UDim2.new(1, -52, 0, 18),
	Text="Click a soul. Read it. Select it. The system may disagree.",
	Font=Enum.Font.Gotham,
	TextSize=14,
	TextColor3=Color3.fromRGB(190,190,200),
	TextXAlignment=Enum.TextXAlignment.Left,
	TextTransparency=0.1,
	ZIndex=40,
}, root)

local main = make("Frame", {
	BackgroundTransparency=1,
	AnchorPoint=Vector2.new(0.5,1),
	Position=UDim2.new(0.5,0,1,-18),
	Size=UDim2.new(1,-48,1,-100),
	ZIndex=40,
	Active=false,
}, root)

make("UIListLayout", {
	FillDirection=Enum.FillDirection.Horizontal,
	Padding=UDim.new(0, 18),
	HorizontalAlignment=Enum.HorizontalAlignment.Center,
	VerticalAlignment=Enum.VerticalAlignment.Center,
}, main)

local center = make("Frame", {
	LayoutOrder=1,
	Size = UDim2.new(0, 560, 0, 560),
	BackgroundTransparency = 1,
	ZIndex = 60,
	Active=false,
}, main)

local ringContainer = make("Frame", {
	Size = UDim2.fromScale(1,1),
	BackgroundTransparency = 1,
	ZIndex = 80,
	Active=false,
}, center)

-- Selected soul lives above blur + dim overlays
local focusLayer = make("Frame", {
	Size = UDim2.fromScale(1,1),
	BackgroundTransparency = 1,
	ZIndex = 240,
	Active=false,
}, center)

-- Blur overlay on ring side
local blurScreen = make("Frame", {
	Visible = false,
	Active = false,
	Size = UDim2.fromScale(1,1),
	BackgroundColor3 = Color3.fromRGB(0,0,0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 180,
}, center)

local blurScan = make("Frame", {Size=UDim2.fromScale(1,1), BackgroundTransparency=1, ZIndex=181, Active=false}, blurScreen)
for i=1, 160 do
	make("Frame", {
		Position = UDim2.new(0,0,(i-1)/160,0),
		Size = UDim2.new(1,0,0,1),
		BackgroundColor3 = Color3.fromRGB(255,255,255),
		BackgroundTransparency = 0.975,
		BorderSizePixel = 0,
		ZIndex = 181,
		Active=false,
	}, blurScan)
end

local blurNoise = make("Frame", {Size=UDim2.fromScale(1,1), BackgroundTransparency=1, ZIndex=182, Active=false}, blurScreen)
local NOISE_TILES = {}
for i=1, 55 do
	local n = make("Frame", {
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(255,255,255),
		BackgroundTransparency = 0.945,
		Size = UDim2.new(0, snapPx(math.random(18, 44),2), 0, snapPx(math.random(8, 22),2)),
		Position = UDim2.new(math.random(), snapPx(math.random(-40,40),2), math.random(), snapPx(math.random(-40,40),2)),
		ZIndex = 182,
		Active=false,
	}, blurNoise)
	table.insert(NOISE_TILES, n)
end

-- Info panel (stats) always clean
local info = make("Frame", {
	LayoutOrder=2,
	Size = UDim2.new(1, -578, 0, 560),
	BackgroundColor3 = Color3.fromRGB(10,10,14),
	BorderSizePixel = 0,
	ZIndex = 260,
	Active=false,
}, main)
addRoughBorder(info, Color3.fromRGB(255,220,140), 266)

local infoSlide = make("Frame", {
	BackgroundTransparency=1,
	Size=UDim2.fromScale(1,1),
	Position=UDim2.new(0, 30, 0, 0),
	ZIndex=270,
	Active=false,
}, info)

local infoTitle = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0, 18, 0, 14),
	Size=UDim2.new(1,-36,0,28),
	Text="—",
	Font=Enum.Font.GothamBlack,
	TextSize=22,
	TextColor3=Color3.fromRGB(245,245,245),
	TextXAlignment=Enum.TextXAlignment.Left,
	ZIndex=270,
}, infoSlide)

local infoBody = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0, 18, 0, 52),
	Size=UDim2.new(1,-36,1,-148),
	Text="Pick a soul to inspect.\n\nNothing happens until you press SELECT.",
	Font=Enum.Font.Gotham,
	TextSize=14,
	TextColor3=Color3.fromRGB(220,220,230),
	TextXAlignment=Enum.TextXAlignment.Left,
	TextYAlignment=Enum.TextYAlignment.Top,
	TextWrapped=true,
	RichText=true,
	ZIndex=270,
}, infoSlide)

local sysLine = make("TextLabel", {
	BackgroundTransparency=1,
	Position=UDim2.new(0, 18, 1, -96),
	Size=UDim2.new(1,-36,0,18),
	Text="",
	Font=Enum.Font.Code,
	TextSize=14,
	TextColor3=Color3.fromRGB(255,60,60),
	TextXAlignment=Enum.TextXAlignment.Left,
	TextTransparency=0.05,
	ZIndex=270,
}, infoSlide)

local btnRow = make("Frame", {
	BackgroundTransparency=1,
	AnchorPoint=Vector2.new(0.5,1),
	Position=UDim2.new(0.5,0,1,-18),
	Size=UDim2.new(1,-36,0,54),
	ZIndex=270,
	Active=false,
}, infoSlide)
make("UIListLayout", {
	FillDirection=Enum.FillDirection.Horizontal,
	Padding=UDim.new(0,10),
	HorizontalAlignment=Enum.HorizontalAlignment.Right,
	VerticalAlignment=Enum.VerticalAlignment.Center,
}, btnRow)

local function actionBtn(text, color)
	local b = make("TextButton", {
		Size=UDim2.new(0,160,0,46),
		BackgroundColor3=Color3.fromRGB(18,18,24),
		BorderSizePixel=0,
		AutoButtonColor=false,
		Text=text,
		Font=Enum.Font.GothamBlack,
		TextSize=18,
		TextColor3=Color3.fromRGB(245,245,245),
		ZIndex=275,
		Active=true,
	}, btnRow)
	addRoughBorder(b, color, 276)
	return b
end

local bBack = actionBtn("Back", Color3.fromRGB(255,220,140))
local bSelect = actionBtn("Select", Color3.fromRGB(255,60,60))
bSelect.Active = false
bSelect.TextTransparency = 0.45

-- DIM MASK: covers everything except stats panel rectangle
local dimMask = make("Frame", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1,1),
	ZIndex = 170,
	Active=false, -- IMPORTANT: never block input
}, root)

local dimTop = make("Frame", {BorderSizePixel=0, BackgroundColor3=Color3.fromRGB(0,0,0), BackgroundTransparency=1, ZIndex=171, Active=false}, dimMask)
local dimBottom = make("Frame", {BorderSizePixel=0, BackgroundColor3=Color3.fromRGB(0,0,0), BackgroundTransparency=1, ZIndex=171, Active=false}, dimMask)
local dimLeft = make("Frame", {BorderSizePixel=0, BackgroundColor3=Color3.fromRGB(0,0,0), BackgroundTransparency=1, ZIndex=171, Active=false}, dimMask)
local dimRight = make("Frame", {BorderSizePixel=0, BackgroundColor3=Color3.fromRGB(0,0,0), BackgroundTransparency=1, ZIndex=171, Active=false}, dimMask)

local function setDimMaskAlpha(alpha)
	local t = 1 - math.clamp(alpha or 0, 0, 1)
	dimTop.BackgroundTransparency = t
	dimBottom.BackgroundTransparency = t
	dimLeft.BackgroundTransparency = t
	dimRight.BackgroundTransparency = t
end

local function layoutDimMask()
	local W, H = root.AbsoluteSize.X, root.AbsoluteSize.Y
	local p = info.AbsolutePosition
	local s = info.AbsoluteSize
	local ix, iy, iw, ih = p.X, p.Y, s.X, s.Y

	dimTop.Position = UDim2.new(0,0, 0,0)
	dimTop.Size = UDim2.new(1,0, 0, math.max(0, iy))

	dimBottom.Position = UDim2.new(0,0, 0, iy + ih)
	dimBottom.Size = UDim2.new(1,0, 0, math.max(0, H - (iy + ih)))

	dimLeft.Position = UDim2.new(0,0, 0, iy)
	dimLeft.Size = UDim2.new(0, math.max(0, ix), 0, ih)

	dimRight.Position = UDim2.new(0, ix + iw, 0, iy)
	dimRight.Size = UDim2.new(0, math.max(0, W - (ix + iw)), 0, ih)
end

-- =========================
-- Pixel heart
-- =========================
local HEART_16 = {
	"0001100000011000",
	"0011110000111100",
	"0111111001111110",
	"1111111111111111",
	"1111111111111111",
	"1111111111111111",
	"0111111111111110",
	"0011111111111100",
	"0001111111111000",
	"0000111111110000",
	"0000011111100000",
	"0000001111000000",
	"0000000110000000",
	"0000000010000000",
	"0000000000000000",
	"0000000000000000",
}

local function parseMask(maskStrings)
	local on = {}
	for y=1,16 do
		local row = maskStrings[y]
		for x=1,16 do
			if row:sub(x,x) == "1" then
				on[y*100 + x] = true
			end
		end
	end
	return on
end

local HEART_ON = parseMask(HEART_16)

local function isOn(on, x, y)
	return on[y*100 + x] == true
end

local function computeOutlineOutside(on)
	local out = {}
	for y=1,16 do
		for x=1,16 do
			if isOn(on, x, y) then
				for oy=-1,1 do
					for ox=-1,1 do
						if not (ox==0 and oy==0) then
							local nx, ny = x+ox, y+oy
							if nx>=1 and nx<=16 and ny>=1 and ny<=16 then
								if not isOn(on, nx, ny) then
									out[ny*100 + nx] = true
								end
							end
						end
					end
				end
			end
		end
	end
	for k,_ in pairs(on) do out[k] = nil end
	return out
end

local HEART_OUT = computeOutlineOutside(HEART_ON)

local function buildHeartOnce(parent, fillColor, pixelSize)
	local ps = pixelSize or 4
	local sizePx = 16 * ps

	local grid = make("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(0, sizePx, 0, sizePx),
		Active = false,
	}, parent)
	grid.AnchorPoint = Vector2.new(0.5,0.5)
	grid.Position = UDim2.fromScale(0.5,0.5)

	local outlineColor = Color3.fromRGB(0,0,0)

	local halo = make("Frame", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Visible=true, Active=false}, grid)
	local outline = make("Frame", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Active=false}, grid)
	local fill = make("Frame", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1), Active=false}, grid)

	halo.ZIndex = (parent.ZIndex or 1) + 0
	outline.ZIndex = halo.ZIndex + 1
	fill.ZIndex = outline.ZIndex + 1
	grid.ZIndex = fill.ZIndex

	local offsets = {{-1,0},{1,0},{0,-1},{0,1}}

	for y=1,16 do
		for x=1,16 do
			if HEART_OUT[y*100 + x] then
				if ((x+y) % 2 == 0) then
					for _,o in ipairs(offsets) do
						make("Frame", {
							Size = UDim2.new(0, ps, 0, ps),
							Position = UDim2.new(0, (x-1)*ps + o[1]*ps, 0, (y-1)*ps + o[2]*ps),
							BackgroundColor3 = fillColor,
							BackgroundTransparency = 0.80,
							BorderSizePixel = 0,
							ZIndex = halo.ZIndex,
							Active=false,
						}, halo)
					end
				end
			end
		end
	end

	for y=1,16 do
		for x=1,16 do
			if HEART_OUT[y*100 + x] then
				make("Frame", {
					Size = UDim2.new(0, ps, 0, ps),
					Position = UDim2.new(0, (x-1)*ps, 0, (y-1)*ps),
					BackgroundColor3 = outlineColor,
					BorderSizePixel = 0,
					ZIndex = outline.ZIndex,
					Active=false,
				}, outline)
			end
		end
	end

	local shade = Color3.fromRGB(
		math.floor(fillColor.R*255*0.78),
		math.floor(fillColor.G*255*0.78),
		math.floor(fillColor.B*255*0.78)
	)

	for y=1,16 do
		for x=1,16 do
			if HEART_ON[y*100 + x] then
				local col = fillColor
				if y >= 10 and x >= 9 then col = shade end
				make("Frame", {
					Size = UDim2.new(0, ps, 0, ps),
					Position = UDim2.new(0, (x-1)*ps, 0, (y-1)*ps),
					BackgroundColor3 = col,
					BorderSizePixel = 0,
					ZIndex = fill.ZIndex,
					Active=false,
				}, fill)
			end
		end
	end

	local handle = {}
	function handle:SetBlur(on) halo.Visible = (on == true) end
	return handle
end

-- =========================
-- Ring + inspect behavior
-- =========================
local soulsUI = {}
local ringRadius = 210
local spin = 0
local connRender

local selectedSoul = nil
local pickedSoulKey = nil
local inspectMode = false
local exitingInspect = false

local selectedLift = {
	active = false,
	wrap = nil,
	origParent = nil,
	origPos = nil,
	origSize = nil,
	origZ = nil,
}

local function computeRingRadius()
	local sz = center.AbsoluteSize
	local minSide = math.min(sz.X, sz.Y)
	ringRadius = math.clamp(math.floor(minSide * 0.40), 150, 245)
end

local function ringSizeFromY(y)
	local depth = (y / ringRadius + 1) * 0.5
	return 104 + depth * 26
end

local function buildLoreText(soul)
	local loreText = table.concat(soul.lore, "\n\n")
	local p = "<b>LORE</b>\n" .. loreText .. "\n\n"
	p ..= "<b>PASSIVES</b>\n• " .. table.concat(soul.passives, "\n• ") .. "\n\n"
	p ..= "<b>ACTIVES</b>\n• " .. table.concat(soul.actives, "\n• ") .. "\n\n"
	p ..= "<b>DRAWBACKS</b>\n• " .. table.concat(soul.drawbacks, "\n• ")
	return p
end

local function liftSelectedWrap(wrap)
	if selectedLift.active then return end
	selectedLift.active = true
	selectedLift.wrap = wrap
	selectedLift.origParent = wrap.Parent
	selectedLift.origPos = wrap.Position
	selectedLift.origSize = wrap.Size
	selectedLift.origZ = wrap.ZIndex

	wrap.Parent = focusLayer
	wrap.ZIndex = 241
	for _,d in ipairs(wrap:GetDescendants()) do
		if d:IsA("GuiObject") then d.ZIndex = 242 end
	end
end

local function restoreSelectedWrap()
	if not selectedLift.active then return end
	local wrap = selectedLift.wrap
	if wrap and wrap.Parent then
		wrap.Parent = selectedLift.origParent
		wrap.Position = selectedLift.origPos
		wrap.Size = selectedLift.origSize
		wrap.ZIndex = selectedLift.origZ or 80
	end
	selectedLift.active = false
	selectedLift.wrap = nil
	selectedLift.origParent = nil
	selectedLift.origPos = nil
	selectedLift.origSize = nil
	selectedLift.origZ = nil
end

-- Gap animation state
local gapAnim = {
	active = false,
	start = 0,
	dur = 0.26,
	from = {},
	to = {},
}

local function startGapAnim(toMap, dur)
	gapAnim.active = true
	gapAnim.start = os.clock()
	gapAnim.dur = dur or 0.26
	gapAnim.from = {}
	gapAnim.to = {}

	for _,s in ipairs(soulsUI) do
		gapAnim.from[s.soul.key] = s.curOffset or s.baseOffset or 0
		gapAnim.to[s.soul.key] = toMap[s.soul.key] or (s.baseOffset or 0)
	end
end

local function computePackedOffsets(selectedKey)
	-- pack NON-selected evenly around full ring (gap closes)
	local order = {}
	for _,s in ipairs(soulsUI) do
		if s.soul.key ~= selectedKey then
			table.insert(order, s)
		end
	end
	table.sort(order, function(a,b) return (a.index or 0) < (b.index or 0) end)

	local n = #order
	local map = {}
	if n <= 0 then return map end

	for k, s in ipairs(order) do
		map[s.soul.key] = (k-1) * (math.pi*2 / n)
	end
	return map
end

local function computeOriginalOffsets()
	local map = {}
	for _,s in ipairs(soulsUI) do
		map[s.soul.key] = s.baseOffset or 0
	end
	return map
end

local function applyInspectVisuals()
	for _, s in ipairs(soulsUI) do
		local isSel = (inspectMode and selectedSoul and s.soul.key == selectedSoul.key)
		if isSel then
			s.heart:SetBlur(false)
			s.glow.Visible = true
			tween(s.wrap, {Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 240, 0, 240)}, 0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
			tween(s.caption, {TextTransparency = 0.10}, 0.12)
		elseif inspectMode then
			s.heart:SetBlur(true)
			s.glow.Visible = false
			tween(s.wrap, {Size = UDim2.new(0, 86, 0, 86)}, 0.14)
			tween(s.caption, {TextTransparency = 0.88}, 0.12)
		else
			s.heart:SetBlur(true)
			s.glow.Visible = false
			tween(s.caption, {TextTransparency = 0.35}, 0.12)
		end
	end
end

local DIM_ALPHA = 0.35
local BLUR_ALPHA = 0.55
local GAP_DUR = 0.28

local function enterInspect(soul)
	inspectMode = true
	exitingInspect = false
	selectedSoul = soul
	pickedSoulKey = soul.key

	bSelect.Active = true
	bSelect.TextTransparency = 0

	layoutDimMask()
	tween(dimTop, {BackgroundTransparency = 1 - DIM_ALPHA}, 0.18)
	tween(dimBottom, {BackgroundTransparency = 1 - DIM_ALPHA}, 0.18)
	tween(dimLeft, {BackgroundTransparency = 1 - DIM_ALPHA}, 0.18)
	tween(dimRight, {BackgroundTransparency = 1 - DIM_ALPHA}, 0.18)

	blurScreen.Visible = true
	blurScreen.BackgroundTransparency = 1
	tween(blurScreen, {BackgroundTransparency = 1 - BLUR_ALPHA}, 0.18)

	for _, s in ipairs(soulsUI) do
		if s.soul.key == soul.key then
			liftSelectedWrap(s.wrap)
			break
		end
	end

	local packed = computePackedOffsets(soul.key)
	startGapAnim(packed, GAP_DUR)

	infoSlide.Position = UDim2.new(0, 40, 0, 0)
	tween(infoSlide, {Position = UDim2.new(0, 0, 0, 0)}, 0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

	infoTitle.Text = soul.label
	infoTitle.TextColor3 = soul.color
	infoBody.Text = buildLoreText(soul)
	sysLine.Text = ""
	glitchBurst(1)

	applyInspectVisuals()
end

local function exitInspect()
	if not inspectMode or exitingInspect then return end
	exitingInspect = true

	local original = computeOriginalOffsets()
	startGapAnim(original, GAP_DUR)

	local frozenSpin = spin

	local selWrap
	local selOffset
	for _, s in ipairs(soulsUI) do
		if selectedSoul and s.soul.key == selectedSoul.key then
			selWrap = s.wrap
			selOffset = (s.baseOffset or 0)
			break
		end
	end

	if selWrap and selOffset then
		computeRingRadius()
		local a = frozenSpin + selOffset
		local x = math.cos(a) * ringRadius
		local y = math.sin(a) * ringRadius
		local size = ringSizeFromY(y)

		tween(selWrap, {
			Position = UDim2.new(0.5, x, 0.5, y),
			Size = UDim2.new(0, size, 0, size),
		}, GAP_DUR, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	end

	task.delay(GAP_DUR + 0.02, function()
		restoreSelectedWrap()

		inspectMode = false
		exitingInspect = false
		selectedSoul = nil
		pickedSoulKey = nil

		bSelect.Active = false
		bSelect.TextTransparency = 0.45

		tween(dimTop, {BackgroundTransparency = 1}, 0.16)
		tween(dimBottom, {BackgroundTransparency = 1}, 0.16)
		tween(dimLeft, {BackgroundTransparency = 1}, 0.16)
		tween(dimRight, {BackgroundTransparency = 1}, 0.16)

		tween(blurScreen, {BackgroundTransparency = 1}, 0.12)
		task.delay(0.13, function()
			if not inspectMode then blurScreen.Visible = false end
		end)

		infoTitle.Text = "—"
		infoTitle.TextColor3 = Color3.fromRGB(245,245,245)
		infoBody.Text = "Pick a soul to inspect.\n\nNothing happens until you press SELECT."
		sysLine.Text = ""

		applyInspectVisuals()
	end)
end

local function buildSouls()
	for _, s in ipairs(soulsUI) do
		if s.wrap then s.wrap:Destroy() end
	end
	soulsUI = {}

	for i, soul in ipairs(SOULS) do
		local wrap = make("Frame", {
			AnchorPoint=Vector2.new(0.5,0.5),
			Position=UDim2.fromScale(0.5,0.5),
			Size=UDim2.new(0,112,0,112),
			BackgroundTransparency=1,
			ZIndex=80,
			Active=false,
		}, ringContainer)

		local btn = make("TextButton", {
			AnchorPoint=Vector2.new(0.5,0.5),
			Position=UDim2.fromScale(0.5,0.5),
			Size=UDim2.fromScale(1,1),
			BackgroundTransparency=1,
			Text="",
			AutoButtonColor=false,
			ZIndex=81,
			Active=true,
		}, wrap)

		local iconWrap = make("Frame", {
			AnchorPoint=Vector2.new(0.5,0.5),
			Position=UDim2.fromScale(0.5,0.46),
			Size=UDim2.new(0,92,0,92),
			BackgroundColor3=Color3.fromRGB(0,0,0),
			BackgroundTransparency=0.50,
			BorderSizePixel=0,
			ZIndex=82,
			Active=false,
		}, btn)
		addRoughBorder(iconWrap, Color3.fromRGB(255,220,140), 84)

		local glow = make("Frame", {
			BackgroundColor3=soul.color,
			BackgroundTransparency=0.92,
			BorderSizePixel=0,
			Size=UDim2.fromScale(1,1),
			ZIndex=83,
			Visible=false,
			Active=false,
		}, iconWrap)

		local pixelsHost = make("Frame", {BackgroundTransparency=1, Size=UDim2.fromScale(1,1), ZIndex=85, Active=false}, iconWrap)
		local heart = buildHeartOnce(pixelsHost, soul.color, 4)
		heart:SetBlur(true)

		local caption = make("TextLabel", {
			BackgroundTransparency=1,
			AnchorPoint=Vector2.new(0.5,0),
			Position=UDim2.new(0.5,0,1,-4),
			Size=UDim2.new(0,180,0,18),
			Text=soul.label,
			Font=Enum.Font.GothamBlack,
			TextSize=12,
			TextColor3=Color3.fromRGB(245,245,245),
			TextTransparency=0.35,
			TextXAlignment=Enum.TextXAlignment.Center,
			TextTruncate=Enum.TextTruncate.AtEnd,
			ZIndex=81,
		}, wrap)

		btn.MouseButton1Click:Connect(function()
			if inspectMode and not exitingInspect then
				exitInspect()
				task.delay(GAP_DUR + 0.05, function()
					enterInspect(soul)
				end)
			elseif not inspectMode then
				enterInspect(soul)
			end
		end)

		local baseOffset = (i-1)*(math.pi*2/#SOULS)

		table.insert(soulsUI, {
			index = i,
			wrap=wrap,
			caption=caption,
			soul=soul,
			glow=glow,
			heart=heart,
			baseOffset=baseOffset,
			curOffset=baseOffset,
		})
	end
end

local function updateRing(dt)
	computeRingRadius()

	if not exitingInspect then
		local speed = inspectMode and 0.12 or 0.18
		spin += dt * speed
	end

	if gapAnim.active then
		local t = (os.clock() - gapAnim.start) / gapAnim.dur
		local a = easeInOutQuad(t)
		for _,s in ipairs(soulsUI) do
			local from = gapAnim.from[s.soul.key] or s.curOffset or 0
			local to = gapAnim.to[s.soul.key] or from
			s.curOffset = lerp(from, to, a)
		end
		if t >= 1 then gapAnim.active = false end
	end

	for _, s in ipairs(soulsUI) do
		if selectedLift.active and selectedSoul and s.soul.key == selectedSoul.key then
			continue
		end

		local a = spin + (s.curOffset or s.baseOffset or 0)
		local x = math.cos(a) * ringRadius
		local y = math.sin(a) * ringRadius

		s.wrap.Position = UDim2.new(0.5, x, 0.5, y)

		local size = ringSizeFromY(y)
		if not inspectMode then
			s.wrap.Size = UDim2.new(0, size, 0, size)
		end
	end
end

-- =========================
-- FORCED SOUL REASSIGN (the missing "error" moment)
-- =========================
local FORCED_REASSIGN_ENABLED = true

-- Put any souls you want to "reject" here:
-- BLOCKED_SOULS["JUSTICE"] = true, etc.
local BLOCKED_SOULS = {
	-- ["JUSTICE"] = true,
}

local RANDOM_REJECT_CHANCE = 0.0
local MAX_REASSIGN_ATTEMPTS = 6

local function isSoulBlocked(key)
	if not FORCED_REASSIGN_ENABLED then return false end
	if BLOCKED_SOULS[key] then return true end
	if RANDOM_REJECT_CHANCE > 0 and math.random() < RANDOM_REJECT_CHANCE then return true end
	return false
end

local function pickForcedSoul(excludeKey)
	local candidates = {}
	for _, s in ipairs(SOULS) do
		if s.key ~= excludeKey and not BLOCKED_SOULS[s.key] then
			table.insert(candidates, s)
		end
	end
	if #candidates == 0 then
		for _, s in ipairs(SOULS) do
			if s.key ~= excludeKey then table.insert(candidates, s) end
		end
	end
	if #candidates == 0 then return nil end
	return candidates[math.random(1, #candidates)]
end

local function hardGlitchShake(duration, strengthPx)
	duration = duration or 0.45
	strengthPx = strengthPx or 10
	local t0 = os.clock()
	local basePos = ringContainer.Position
	local basePos2 = focusLayer.Position
	local basePos3 = infoSlide.Position

	while os.clock() - t0 < duration do
		local dx = snapPx(math.random(-strengthPx, strengthPx), 1)
		local dy = snapPx(math.random(-strengthPx, strengthPx), 1)

		ringContainer.Position = UDim2.new(basePos.X.Scale, basePos.X.Offset + dx, basePos.Y.Scale, basePos.Y.Offset + dy)
		focusLayer.Position   = UDim2.new(basePos2.X.Scale, basePos2.X.Offset - dx, basePos2.Y.Scale, basePos2.Y.Offset + dy)
		infoSlide.Position    = UDim2.new(basePos3.X.Scale, basePos3.X.Offset + dx, basePos3.Y.Scale, basePos3.Y.Offset - dy)

		if math.random() < 0.70 then glitchBurst(1.6) end
		task.wait(0.016)
	end

	ringContainer.Position = basePos
	focusLayer.Position   = basePos2
	infoSlide.Position    = basePos3
end

local function playForcedReassignSequence(oldKey, newSoul)
	sysLine.TextColor3 = Color3.fromRGB(255, 60, 60)
	sysLine.Text = ("ERROR: SOUL '%s' REJECTED. FORCING REASSIGN…"):format(tostring(oldKey))

	tween(dimTop,    {BackgroundTransparency = 1 - 0.55}, 0.06)
	tween(dimBottom, {BackgroundTransparency = 1 - 0.55}, 0.06)
	tween(dimLeft,   {BackgroundTransparency = 1 - 0.55}, 0.06)
	tween(dimRight,  {BackgroundTransparency = 1 - 0.55}, 0.06)

	blurScreen.Visible = true
	tween(blurScreen, {BackgroundTransparency = 1 - 0.75}, 0.06)

	hardGlitchShake(0.55, 12)

	local punch = make("Frame", {
		BackgroundColor3 = Color3.fromRGB(0,0,0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1,1),
		ZIndex = 999999,
		Active=false,
	}, root)
	tween(punch, {BackgroundTransparency = 0.15}, 0.05)
	task.wait(0.06)
	tween(punch, {BackgroundTransparency = 1}, 0.10)
	task.delay(0.12, function() if punch and punch.Parent then punch:Destroy() end end)

	if newSoul then
		infoTitle.Text = newSoul.label
		infoTitle.TextColor3 = newSoul.color
		infoBody.Text = buildLoreText(newSoul)
		sysLine.TextColor3 = Color3.fromRGB(255, 220, 140)
		sysLine.Text = ("ASSIGNED: %s"):format(newSoul.key)
	end
end

-- =========================
-- Open/Close
-- =========================
local drift = 0
local vfxT = 0

local function open()
	gui.Enabled = true

	inspectMode = false
	exitingInspect = false
	selectedSoul = nil
	pickedSoulKey = nil
	bSelect.Active = false
	bSelect.TextTransparency = 0.45

	restoreSelectedWrap()
	blurScreen.Visible = false
	blurScreen.BackgroundTransparency = 1
	setDimMaskAlpha(0)

	buildSouls()
	applyInspectVisuals()
	layoutDimMask()

	if connRender then connRender:Disconnect() end
	connRender = RunService.RenderStepped:Connect(function(dt)
		updateRing(dt)

		if inspectMode or exitingInspect then
			layoutDimMask()
		end

		if blurScreen.Visible then
			drift += dt * 10
			blurScan.Position = UDim2.new(0,0,0, snapPx(drift % 3, 1))
			if math.random() < 0.25 then
				for _,tile in ipairs(NOISE_TILES) do
					if math.random() < 0.15 then
						tile.BackgroundTransparency = 0.93 + (math.random() * 0.06)
						tile.Position = UDim2.new(math.random(), snapPx(math.random(-40,40),2), math.random(), snapPx(math.random(-40,40),2))
					end
				end
			end
		end

		vfxT += dt
		if vfxT > 0.02 then
			vfxT = 0
			for _,b in ipairs(vfxBlocks) do
				local g = b.gui
				local p = g.Position
				local nx = p.X.Scale + b.vx
				local ny = p.Y.Scale + b.vy
				if nx < -0.05 then nx = 1.05 end
				if nx > 1.05 then nx = -0.05 end
				if ny < -0.05 then ny = 1.05 end
				if ny > 1.05 then ny = -0.05 end
				g.Position = UDim2.new(nx, p.X.Offset, ny, p.Y.Offset)
				if math.random() < 0.05 then
					g.BackgroundTransparency = 0.955 + (math.random()*0.04)
				end
			end
			for _,d in ipairs(dust) do
				local g = d.gui
				local p = g.Position
				local nx = p.X.Scale + d.vx
				local ny = p.Y.Scale + d.vy
				if nx < -0.02 then nx = 1.02 end
				if nx > 1.02 then nx = -0.02 end
				if ny < -0.02 then ny = 1.02 end
				if ny > 1.02 then ny = -0.02 end
				g.Position = UDim2.new(nx, 0, ny, 0)
			end
		end

		if math.random() < 0.03 then glitchBurst(1) end
	end)
end

local function close()
	blurScreen.Visible = false
	setDimMaskAlpha(0)
	restoreSelectedWrap()
	if connRender then connRender:Disconnect(); connRender = nil end
	gui.Enabled = false
end

-- =========================
-- Buttons
-- =========================
bBack.MouseButton1Click:Connect(function()
	if inspectMode and not exitingInspect then
		exitInspect()
	else
		close()
	end
end)

bSelect.MouseButton1Click:Connect(function()
	if not pickedSoulKey or exitingInspect then return end

	-- lock UI while we do rejection/confirm
	bSelect.Active = false
	bBack.Active = false

	local chosenKey = tostring(pickedSoulKey)
	local attempts = 0

	while isSoulBlocked(chosenKey) and attempts < MAX_REASSIGN_ATTEMPTS do
		attempts += 1
		local forced = pickForcedSoul(chosenKey)
		if not forced then break end

		playForcedReassignSequence(chosenKey, forced)

		chosenKey = forced.key
		selectedSoul = forced
		pickedSoulKey = forced.key

		-- keep the selected displayed as the forced one
		restoreSelectedWrap()
		for _, s in ipairs(soulsUI) do
			if s.soul.key == forced.key then
				liftSelectedWrap(s.wrap)
				break
			end
		end
		applyInspectVisuals()
	end

	-- ✅ THIS IS THE MISSING PHASE 2:
	-- Tell StartMenu what soul is locked, then tell it to open slot picker for NewGame.
	-- ✅ Persist chosen soul (server-authoritative if SoulSwitchRE exists)
	setSoulServer(chosenKey)

	-- ✅ Your existing pipeline
	-- ✅ Store pending soul choice (StartMenu will persist it into the chosen save slot)
	setPendingSoul(chosenKey)

	-- ✅ Your existing StartMenu bridge pipeline
	bridge:Fire("Chosen", chosenKey)
	bridge:Fire("Mode", "NewGame")

	close()



	-- restore button actives for next open
	bBack.Active = true
end)

-- =========================
-- Bridge input
-- =========================
bridge.Event:Connect(function(kind)
	if kind == "Open" then
		open()
	end
end)

print("[SoulSelect] Loaded (Select now fires bridge Chosen+Mode; forced reassignment supported).")
