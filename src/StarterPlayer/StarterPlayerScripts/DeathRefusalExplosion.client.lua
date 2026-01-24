-- StarterPlayerScripts/DeathRefusalExplosion.client.lua
-- Listens for DeathRefusalExplosionRE broadcasts.
-- Handles:
--  - kind="camera"  (leave your existing camera logic if you have it)
--  - kind="impactFrames" (Lighting.RefusalFrame1 -> RefusalFrame2)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RE = Remotes:WaitForChild("DeathRefusalExplosionRE")

-- Debounce so multiple triggers don't strobe-spam
local playingImpact = false
local impactToken = 0

local function setEnabledSafe(effect: Instance?, on: boolean)
	if not effect then return end
	-- Most Lighting effects use .Enabled (ColorCorrectionEffect, BloomEffect, SunRaysEffect, etc.)
	local ok = pcall(function()
		if effect:IsA("PostEffect") or effect:IsA("ColorCorrectionEffect") or effect:IsA("BloomEffect") or effect:IsA("SunRaysEffect") then
			effect.Enabled = on
		elseif effect:FindFirstChild("Enabled") ~= nil then
			(effect :: any).Enabled = on
		end
	end)
	if not ok then
		-- ignore
	end
end

local function playImpactFrames(frame1Name: string, frame2Name: string, total: number, split: number)
	total = math.clamp(tonumber(total) or 0.35, 0.2, 0.8)
	split = math.clamp(tonumber(split) or 0.5, 0.1, 0.9)

	local f1 = Lighting:FindFirstChild(frame1Name)
	local f2 = Lighting:FindFirstChild(frame2Name)

	if not f1 and not f2 then
		warn("[DeathRefusalExplosion.client] Impact frames not found in Lighting:", frame1Name, frame2Name)
		return
	end

	impactToken += 1
	local myToken = impactToken
	playingImpact = true

	-- Ensure both start off
	setEnabledSafe(f1, false)
	setEnabledSafe(f2, false)

	local t1 = total * split
	local t2 = total - t1

	-- Frame 1
	setEnabledSafe(f1, true)
	task.delay(t1, function()
		if myToken ~= impactToken then return end
		setEnabledSafe(f1, false)

		-- Frame 2
		setEnabledSafe(f2, true)
		task.delay(t2, function()
			if myToken ~= impactToken then return end
			setEnabledSafe(f2, false)
			playingImpact = false
		end)
	end)
end

RE.OnClientEvent:Connect(function(data)
	if typeof(data) ~= "table" then return end

	if data.kind == "impactFrames" then
		-- Don’t stack; restart cleanly if spammed
		local frame1 = tostring(data.frame1 or "RefusalFrame1")
		local frame2 = tostring(data.frame2 or "RefusalFrame2")
		playImpactFrames(frame1, frame2, tonumber(data.total) or 0.35, tonumber(data.split) or 0.5)
		return
	end

	if data.kind == "camera" then
		-- If you already have camera code elsewhere, ignore this block or merge it.
		-- Leaving as a placeholder to not break your existing system.
		return
	end
end)
