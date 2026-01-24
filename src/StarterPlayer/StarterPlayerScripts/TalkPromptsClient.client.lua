print("[TalkPromptsClient] Running")
print("[TalkPromptsClient] Running on client:", game.Players.LocalPlayer.Name)


-- StarterPlayerScripts/TalkPromptsClient


local Players = game:GetService("Players")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local dialogueGui = playerGui:WaitForChild("DialogueGui", 10)
assert(dialogueGui, "DialogueGui not found in PlayerGui. Ensure it's in StarterGui and ResetOnSpawn=false.")

local function startDialogue(npcId)
	if _G.StartDialogue then
		_G.StartDialogue(npcId)
	else
		warn("StartDialogue not found. Make sure DialogueClient LocalScript is running in StarterPlayerScripts.")
	end
end

local function findNpcIdFromInstance(inst)
	local current = inst
	while current and current ~= workspace do
		local npcId = current:GetAttribute("NpcId")
		if typeof(npcId) == "string" and npcId ~= "" then
			return npcId
		end
		current = current.Parent
	end
	return nil
end

local function hookPrompt(prompt: ProximityPrompt)
	local npcId = findNpcIdFromInstance(prompt)
	if not npcId then
		-- Not an NPC prompt (no NpcId found up the chain)
		return
	end

	if prompt:GetAttribute("__Hooked") then
		return
	end
	prompt:SetAttribute("__Hooked", true)

	print("[TalkPromptsClient] Hooked prompt:", prompt:GetFullName(), "NpcId:", npcId)

	prompt.Triggered:Connect(function(triggeringPlayer)
		if triggeringPlayer ~= player then return end
		print("[TalkPromptsClient] Triggered:", npcId)
		startDialogue(npcId)
	end)
end

-- Hook existing prompts
for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("ProximityPrompt") then
		hookPrompt(inst)
	end
end

local countPrompts = 0
local countNpcPrompts = 0

for _, inst in ipairs(workspace:GetDescendants()) do
	if inst:IsA("ProximityPrompt") then
		countPrompts += 1
		local npcId = findNpcIdFromInstance(inst)
		if npcId then
			countNpcPrompts += 1
			print("[TalkPromptsClient] Found NPC prompt:", inst:GetFullName(), "NpcId:", npcId)
		else
			-- Uncomment this if you want spam:
			-- print("[TalkPromptsClient] Prompt has NO NpcId in ancestry:", inst:GetFullName())
		end
	end
end

print(("[TalkPromptsClient] Total prompts: %d | NPC prompts: %d"):format(countPrompts, countNpcPrompts))


-- Hook future prompts
workspace.DescendantAdded:Connect(function(inst)
	if inst:IsA("ProximityPrompt") then
		hookPrompt(inst)
	end
end)
