-- StarterPlayerScripts/SongCreditPopup.client.lua
-- Safe, non-crashing song credit popup.
-- Listens for a RemoteEvent if present. Otherwise does nothing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

-- Try to find a remote (supports multiple possible names)
local function findCreditRemote()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	if not remotes then return nil end
	return remotes:FindFirstChild("SongCreditPopupRE")
		or remotes:FindFirstChild("SongCreditRE")
		or remotes:FindFirstChild("SongCredit")
end

local creditRE = findCreditRemote()
if not creditRE then
	-- No remote? Cool. We don't crash and ruin your startup screen.
	return
end

-- Build UI
local gui = Instance.new("ScreenGui")
gui.Name = "SongCreditPopupGui"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 1000000
gui.Parent = pg

local wrap = Instance.new("Frame")
wrap.AnchorPoint = Vector2.new(0.5, 0)
wrap.Position = UDim2.new(0.5, 0, 0, 18)
wrap.Size = UDim2.new(0, 720, 0, 64)
wrap.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
wrap.BackgroundTransparency = 1
wrap.BorderSizePixel = 0
wrap.Parent = gui

local stroke = Instance.new("UIStroke")
stroke.Thickness = 2
stroke.Color = Color3.fromRGB(255, 220, 140)
stroke.Transparency = 1
stroke.Parent = wrap

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 14)
corner.Parent = wrap

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 18, 0, 6)
title.Size = UDim2.new(1, -36, 0, 26)
title.Font = Enum.Font.GothamBlack
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(245, 245, 245)
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextTransparency = 1
title.Text = "Now Playing"
title.Parent = wrap

local body = Instance.new("TextLabel")
body.BackgroundTransparency = 1
body.Position = UDim2.new(0, 18, 0, 32)
body.Size = UDim2.new(1, -36, 0, 24)
body.Font = Enum.Font.Gotham
body.TextSize = 14
body.TextColor3 = Color3.fromRGB(255, 220, 140)
body.TextXAlignment = Enum.TextXAlignment.Left
body.TextTransparency = 1
body.Text = ""
body.Parent = wrap

local showing = false
local currentTween = nil

local function killTween()
	if currentTween then
		pcall(function() currentTween:Cancel() end)
		currentTween = nil
	end
end

local function show(text, duration)
	duration = tonumber(duration) or 4

	killTween()
	showing = true
	wrap.BackgroundTransparency = 1
	stroke.Transparency = 1
	title.TextTransparency = 1
	body.TextTransparency = 1

	body.Text = tostring(text or "")

	-- fade in
	currentTween = TweenService:Create(wrap, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.08
	})
	currentTween:Play()
	TweenService:Create(stroke, TweenInfo.new(0.18), { Transparency = 0.30 }):Play()
	TweenService:Create(title, TweenInfo.new(0.18), { TextTransparency = 0 }):Play()
	TweenService:Create(body, TweenInfo.new(0.18), { TextTransparency = 0 }):Play()

	task.delay(duration, function()
		if not showing then return end
		killTween()
		showing = false
		TweenService:Create(wrap, TweenInfo.new(0.22), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.22), { Transparency = 1 }):Play()
		TweenService:Create(title, TweenInfo.new(0.22), { TextTransparency = 1 }):Play()
		TweenService:Create(body, TweenInfo.new(0.22), { TextTransparency = 1 }):Play()
	end)
end

creditRE.OnClientEvent:Connect(function(payload)
	-- payload can be string OR table
	if type(payload) == "string" then
		show(payload, 4)
		return
	end
	if type(payload) == "table" then
		local song = payload.song or payload.title or "Unknown Track"
		local artist = payload.artist or payload.author or "Unknown Artist"
		local dur = payload.duration or payload.time or 4
		show(("%s  •  %s"):format(tostring(song), tostring(artist)), dur)
	end
end)
