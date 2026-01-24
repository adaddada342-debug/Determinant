local RunService = game:GetService("RunService")

local part = script.Parent
assert(part:IsA("BasePart"), "Parent must be a BasePart")

local SPEED_DEG_PER_SEC = 35 -- X-axis rotation speed

-- Lock the reference orientation so it doesn't drift
local baseCF = part.CFrame
local angle = 0

RunService.RenderStepped:Connect(function(dt)
	angle += math.rad(SPEED_DEG_PER_SEC) * dt
	CFrame.Angles(0, angle, 0) -- yaw (side-to-side)
end)
