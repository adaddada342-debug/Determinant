-- StarterPlayerScripts/DialogueGuiBootstrap.client.lua
-- Guarantees DialogueGui exists in PlayerGui (even if something deletes it).
-- Keeps DialogueClient from exploding on startup.
-- Works with DialogueGuiAutoSetup (which can create it too). This script just ensures resilience.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local pg = player:WaitForChild("PlayerGui")

local function ensureDialogueGui()
	local existing = pg:FindFirstChild("DialogueGui")
	if existing and existing:IsA("ScreenGui") then
		return existing
	end

	-- Try to clone from StarterGui (must be a direct child there)
	local src = StarterGui:FindFirstChild("DialogueGui")
	if not (src and src:IsA("ScreenGui")) then
		-- DialogueGuiAutoSetup can still create it, so don't hard-fail.
		warn("[DialogueGuiBootstrap] DialogueGui not found in StarterGui. AutoSetup may create it.")
		return nil
	end

	local clone = src:Clone()
	clone.ResetOnSpawn = false
	clone.Parent = pg
	return clone
end

-- Initial ensure (give replication a moment)
task.delay(0.15, ensureDialogueGui)
task.delay(0.75, ensureDialogueGui)

-- If something removes it later, put it back.
pg.ChildRemoved:Connect(function(child)
	if child.Name == "DialogueGui" then
		task.defer(ensureDialogueGui)
	end
end)
