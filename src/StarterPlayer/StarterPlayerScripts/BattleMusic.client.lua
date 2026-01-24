-- StarterPlayerScripts/BattleMusic.client.lua
-- Client-only battle music with automatic audio unlock on first user input.
-- Uses only UserInputService.InputBegan (works everywhere).
-- Starts on BattleRE "Begin", stops on "Victory"/"End".

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local plr = Players.LocalPlayer
local pg = plr:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local BattleRE = Remotes:WaitForChild("BattleRE")

-- CONFIG
local BATTLE_MUSIC_ID = "rbxassetid://92255825428297"
local TARGET_VOL = 0.65
local FADE_IN = 0.35
local FADE_OUT = 0.35

-- Internal
local audioUnlocked = false
local wantMusic = false
local currentSound = nil

-- Kill leftovers if script reloads
for _, p in ipairs({SoundService, pg}) do
	for _, ch in ipairs(p:GetChildren()) do
		if ch:IsA("Sound") and ch.Name == "__BattleMusic" then
			ch:Destroy()
		end
	end
end

local function tweenVol(s, vol, dur)
	if not s or not s.Parent then return end
	TweenService:Create(
		s,
		TweenInfo.new(dur or 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Volume = vol }
	):Play()
end

local function stopMusic()
	if not currentSound then return end
	local s = currentSound
	currentSound = nil
	tweenVol(s, 0, FADE_OUT)
	task.delay(FADE_OUT + 0.05, function()
		if s then s:Destroy() end
	end)
end

local function startMusic()
	if not audioUnlocked then return end
	if wantMusic ~= true then return end
	if currentSound then return end

	if typeof(BATTLE_MUSIC_ID) ~= "string" or BATTLE_MUSIC_ID == "" or BATTLE_MUSIC_ID:find("PUT_YOUR_BATTLE_MUSIC_ID_HERE") then
		warn("[BattleMusic] BATTLE_MUSIC_ID not set")
		return
	end

	local s = Instance.new("Sound")
	s.Name = "__BattleMusic"
	s.SoundId = BATTLE_MUSIC_ID
	s.Volume = 0
	s.Looped = true
	s.Parent = SoundService

	currentSound = s

	-- Preload best effort
	pcall(function()
		ContentProvider:PreloadAsync({ s })
	end)

	-- Play locally (best effort)
	pcall(function() SoundService:PlayLocalSound(s) end)
	pcall(function() s:Play() end)

	tweenVol(s, TARGET_VOL, FADE_IN)
end

-- 🔓 Auto-unlock audio (once) on first *real* input
local function unlockAudioOnce()
	if audioUnlocked then return end
	audioUnlocked = true

	-- Silent "ping" helps satisfy autoplay restrictions on some setups
	local ping = Instance.new("Sound")
	ping.Name = "__AudioUnlockPing"
	ping.SoundId = "rbxassetid://9118823101" -- tiny default click-ish sound; replace if you want
	ping.Volume = 0 -- silent, just a gesture-bound play call
	ping.Parent = SoundService
	pcall(function() SoundService:PlayLocalSound(ping) end)
	pcall(function() ping:Play() end)
	task.delay(1, function()
		if ping then ping:Destroy() end
	end)

	startMusic()
end

UserInputService.InputBegan:Connect(function(_, gameProcessed)
	if gameProcessed then return end
	unlockAudioOnce()
end)

-- Battle hooks
BattleRE.OnClientEvent:Connect(function(kind)
	if kind == "Begin" then
		wantMusic = true
		startMusic()
	elseif kind == "Victory" or kind == "End" then
		wantMusic = false
		stopMusic()
	end
end)

print("[BattleMusic] Loaded (auto-unlock on first input).")
