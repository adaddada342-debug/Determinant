-- StarterPlayerScripts/LightingHardReset.client.lua
-- Resets common "flashbang" Lighting offenders on spawn.
-- This does not delete your effects, it just forces safe values.

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")

local function resetEffect(e)
	if e:IsA("BloomEffect") then
		e.Intensity = 0
		e.Threshold = 0.95
		e.Size = 64
	elseif e:IsA("ColorCorrectionEffect") then
		e.Brightness = 0
		e.Contrast = 0
		e.Saturation = 0
		e.TintColor = Color3.new(1,1,1)
	elseif e:IsA("BlurEffect") then
		e.Size = 0
	elseif e:IsA("SunRaysEffect") then
		e.Intensity = 0
		e.Spread = 0.9
	elseif e:IsA("DepthOfFieldEffect") then
		e.Enabled = false
	end
end

local function hardReset()
	-- These two are the usual “why is everything glowing” culprits:
	if Lighting:FindFirstChild("__CataclysmPost") then
		for _, e in ipairs(Lighting.__CataclysmPost:GetChildren()) do
			resetEffect(e)
		end
	end

	-- If you have other custom packs, you can add them here too:
	-- if Lighting:FindFirstChild("__AsrielPost") then ... end

	-- Also check raw Lighting settings that can blow exposure out:
	if Lighting.ExposureCompensation > 0 then
		Lighting.ExposureCompensation = 0
	end
	Lighting.Brightness = math.clamp(Lighting.Brightness, 1, 3)

	-- If you use Atmosphere, density + haze can create that washed-out white look.
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmo then
		atmo.Haze = math.clamp(atmo.Haze, 0, 2)
		atmo.Glare = math.clamp(atmo.Glare, 0, 1)
	end
end

localPlayer = Players.LocalPlayer
localPlayer.CharacterAdded:Connect(function()
	task.wait(0.1) -- let other scripts create their junk
	hardReset()
end)

-- Run once on join too
task.defer(hardReset)
