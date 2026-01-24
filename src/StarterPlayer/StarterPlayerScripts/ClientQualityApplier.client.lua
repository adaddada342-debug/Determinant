local Players = game:GetService("Players")
local player = Players.LocalPlayer

local function apply(q)
	q = math.clamp(tonumber(q) or 7, 1, 10)

	-- Example: set attributes other systems can use
	player:SetAttribute("VFXRateScale", math.clamp(q / 10, 0.1, 1.0))
	player:SetAttribute("AllowHeavyPostFX", q >= 7)
	player:SetAttribute("AllowExtraParticles", q >= 6)

	-- If you have specific effects folders, scale them here:
	-- For example: workspace.Effects has ParticleEmitters
	-- (keep this empty until you decide your structure)
end

apply(player:GetAttribute("GraphicsQuality"))
player:GetAttributeChangedSignal("GraphicsQuality"):Connect(function()
	apply(player:GetAttribute("GraphicsQuality"))
end)
