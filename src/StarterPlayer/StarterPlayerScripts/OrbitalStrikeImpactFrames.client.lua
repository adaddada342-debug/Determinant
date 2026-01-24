-- StarterPlayerScripts/OrbitalStrikeImpactFrames.client.lua
-- Reliable 2-stage impact frames with micro-ramps (no Tween.Completed waits).
-- Triggers ONLY when server sends action == "Impact" on Remotes/OrbitalStrikeFX.
--
-- Requires these DIRECT children of Lighting:
--   LaserCorrection1 (ColorCorrectionEffect)
--   LaserBlur1       (BlurEffect)
--   LaserCorrection2 (ColorCorrectionEffect)
--   LaserBlur2       (BlurEffect)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer
local cam = workspace.CurrentCamera

local Shake = require(player:WaitForChild("PlayerScripts"):WaitForChild("Modules"):WaitForChild("CameraShake"))
local shaker = Shake.new()
shaker:Start(cam)


--============================================================
-- CONFIG
--============================================================
local CONFIG = {
	REMOTES_FOLDER = "Remotes",
	FX_REMOTE_NAME = "OrbitalStrikeFX",
	IMPACT_ACTION = "Impact",

	-- Micro-ramps (smoothness). Keep small.
	RAMP_IN = 0.05,
	HOLD_1  = 0.03,
	RAMP_OUT = 0.06,

	RAMP_IN_2 = 0.05,
	HOLD_2    = 0.05,
	RAMP_OUT_2 = 0.06,

	-- Debug: make it obvious (optional)
	DEBUG = false,
	DEBUG_MULT = 6, -- if DEBUG true, multiplies all durations

	-- Manual local test key
	MANUAL_TEST = true,
	TEST_KEY = Enum.KeyCode.F,

	-- Names
	CC1_NAME = "LaserCorrection1",
	BLUR1_NAME = "LaserBlur1",
	CC2_NAME = "LaserCorrection2",
	BLUR2_NAME = "LaserBlur2",
}

--============================================================
-- Helpers
--============================================================
local function getCC(name: string): ColorCorrectionEffect?
	local inst = Lighting:FindFirstChild(name)
	return (inst and inst:IsA("ColorCorrectionEffect")) and inst or nil
end

local function getBlur(name: string): BlurEffect?
	local inst = Lighting:FindFirstChild(name)
	return (inst and inst:IsA("BlurEffect")) and inst or nil
end

local function tween(inst: Instance, duration: number, props: {})
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tw = TweenService:Create(inst, info, props)
	tw:Play()
	return tw
end

local function disableAll(cc1, b1, cc2, b2)
	if cc1 then cc1.Enabled = false end
	if b1 then b1.Enabled = false end
	if cc2 then cc2.Enabled = false end
	if b2 then b2.Enabled = false end
end

-- Plays one layer by tweening from neutral -> target -> neutral
local function playLayer(cc: ColorCorrectionEffect, blur: BlurEffect, rampIn: number, hold: number, rampOut: number)
	-- Cache your tuned "target" values from Studio
	local targetB = cc.Brightness
	local targetC = cc.Contrast
	local targetS = cc.Saturation
	local targetT = cc.TintColor
	local targetBlur = blur.Size

	-- Enable and start at neutral (no effect)
	cc.Enabled = true
	blur.Enabled = true

	cc.Brightness = 0
	cc.Contrast = 0
	cc.Saturation = 0
	cc.TintColor = Color3.new(1, 1, 1)
	blur.Size = 0

	-- Ramp in
	tween(cc, rampIn, {
		Brightness = targetB,
		Contrast = targetC,
		Saturation = targetS,
		TintColor = targetT,
	})
	tween(blur, rampIn, { Size = targetBlur })
	task.wait(rampIn)

	-- Hold
	task.wait(hold)

	-- Ramp out to neutral
	tween(cc, rampOut, {
		Brightness = 0,
		Contrast = 0,
		Saturation = 0,
		TintColor = Color3.new(1, 1, 1),
	})
	tween(blur, rampOut, { Size = 0 })
	task.wait(rampOut)

	-- Disable and restore tuned target values (so your Studio values remain intact)
	cc.Enabled = false
	blur.Enabled = false

	cc.Brightness = targetB
	cc.Contrast = targetC
	cc.Saturation = targetS
	cc.TintColor = targetT
	blur.Size = targetBlur
end

--============================================================
-- Playback
--============================================================
local playing = false

local function playImpact(reason: string)
	if playing then return end
	playing = true

	local cc1 = getCC(CONFIG.CC1_NAME)
	local b1  = getBlur(CONFIG.BLUR1_NAME)
	local cc2 = getCC(CONFIG.CC2_NAME)
	local b2  = getBlur(CONFIG.BLUR2_NAME)

	if not (cc1 and b1 and cc2 and b2) then
		warn("[ImpactFrames] Missing Lighting effects. Reason:", reason, cc1, b1, cc2, b2)
		playing = false
		return
	end

	local m = CONFIG.DEBUG and CONFIG.DEBUG_MULT or 1

	playLayer(cc1, b1, CONFIG.RAMP_IN*m, CONFIG.HOLD_1*m, CONFIG.RAMP_OUT*m)
	playLayer(cc2, b2, CONFIG.RAMP_IN_2*m, CONFIG.HOLD_2*m, CONFIG.RAMP_OUT_2*m)

	playing = false
end

--============================================================
-- Boot
--============================================================
do
	local cc1 = getCC(CONFIG.CC1_NAME)
	local b1  = getBlur(CONFIG.BLUR1_NAME)
	local cc2 = getCC(CONFIG.CC2_NAME)
	local b2  = getBlur(CONFIG.BLUR2_NAME)
	disableAll(cc1, b1, cc2, b2)
end

-- Manual test
if CONFIG.MANUAL_TEST then
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.KeyCode ~= CONFIG.TEST_KEY then return end
		playImpact("ManualTest")
	end)
end

-- Remote listener (ONLY laser spawn)
local Remotes = ReplicatedStorage:WaitForChild(CONFIG.REMOTES_FOLDER)
local FX = Remotes:WaitForChild(CONFIG.FX_REMOTE_NAME)

FX.OnClientEvent:Connect(function(action, payload)
	if action ~= CONFIG.IMPACT_ACTION then return end
	playImpact("RemoteImpact")
	
	-- Big hit: short and violent
	shaker:Burst(0.45, math.rad(1.8), 22, 14)

	-- Aftershock: delayed smaller rumble
	task.delay(0.18, function()
		shaker:Burst(0.18, math.rad(0.8), 14, 8)
	end)

end)
