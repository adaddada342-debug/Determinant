local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local ExplosionFX = Remotes:WaitForChild("ExplosionFX")

-- Call this whenever you want the explosion
local function TriggerExplosion(pivotCF, scale)
	ExplosionFX:FireAllClients(pivotCF, scale or 1)
end

-- Example: test after 2s at spawn
task.delay(2, function()
	TriggerExplosion(CFrame.new(0, 20, 0), 1)
end)

return TriggerExplosion
