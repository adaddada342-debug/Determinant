-- ServerScriptService/DeterminantCombat/BossTestTrigger.server.lua
-- Creates a basic boss Part with a ProximityPrompt to start bullet hell.

local Players = game:GetService("Players")

local BulletHellService = _G.BulletHellService
assert(BulletHellService, "BulletHellService must load before BossTestTrigger")

local boss = workspace:FindFirstChild("BossDummy")
if not boss then
	boss = Instance.new("Part")
	boss.Name = "BossDummy"
	boss.Anchored = true
	boss.Size = Vector3.new(6, 10, 6)
	boss.Position = Vector3.new(0, 5, -25)
	boss.Color = Color3.fromRGB(20, 20, 20)
	boss.Parent = workspace
end

local prompt = boss:FindFirstChildOfClass("ProximityPrompt")
if not prompt then
	prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Start Bullet Hell"
	prompt.ObjectText = "Boss Dummy"
	prompt.HoldDuration = 0.25
	prompt.MaxActivationDistance = 12
	prompt.Parent = boss
end

prompt.Triggered:Connect(function(plr)
	BulletHellService.StartPhase(plr, boss, "Boss_Default", 10)
end)

print("[DeterminantCombat] BossTestTrigger ready (use the prompt on BossDummy)")
