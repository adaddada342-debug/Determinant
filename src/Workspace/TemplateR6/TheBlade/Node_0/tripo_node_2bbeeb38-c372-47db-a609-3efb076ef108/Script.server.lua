-- Script inside the Scythe Model
local TweenService = game:GetService("TweenService")

local model = script.Parent

-- Pulse settings (subtle = godlike, not a rave)
local brightTransparency = 0.05
local dimTransparency = 0.15
local pulseTime = 2.5

-- Collect all Neon parts in the model
local neonParts = {}
for _, inst in ipairs(model:GetDescendants()) do
	if inst:IsA("BasePart") and inst.Material == Enum.Material.Neon then
		table.insert(neonParts, inst)
	end
end

if #neonParts == 0 then
	warn("[ScythePulse] No Neon BaseParts found under", model:GetFullName())
	return
end

-- Start from bright
for _, p in ipairs(neonParts) do
	p.Transparency = brightTransparency
end

local tweenInfo = TweenInfo.new(
	pulseTime,
	Enum.EasingStyle.Sine,
	Enum.EasingDirection.InOut,
	-1,   -- infinite
	true  -- auto-reverse
)

-- Create + play tweens for each part
local tweens = {}
for _, p in ipairs(neonParts) do
	local tw = TweenService:Create(p, tweenInfo, { Transparency = dimTransparency })
	table.insert(tweens, tw)
	tw:Play()
end

-- Optional: if the model gets removed, clean up tweens
model.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		for _, tw in ipairs(tweens) do
			pcall(function() tw:Cancel() end)
		end
	end
end)
