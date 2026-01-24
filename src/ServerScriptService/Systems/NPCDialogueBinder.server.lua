-- ServerScriptService/Systems/NPCDialogueBinder (Script)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local DialogueEvent = Remotes:WaitForChild("DialogueEvent")

if not DialogueEvent:IsA("RemoteEvent") then
	warn("[NPCDialogueBinder] Remotes/DialogueEvent must be a RemoteEvent, not:", DialogueEvent.ClassName)
	return
end

local function getNpcIdFromPrompt(prompt: ProximityPrompt): string?
	local p = prompt.Parent
	if not p then return nil end

	local model = p:FindFirstAncestorOfClass("Model")
	if not model then return nil end

	local npcId = model:GetAttribute("NpcId")
	if typeof(npcId) == "string" and npcId ~= "" then
		return npcId
	end

	-- No fallback. If you want dialogue, set NpcId.
	warn("[NPCDialogueBinder] Model missing NpcId attribute:", model:GetFullName())
	return nil
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
	if not prompt or not player then return end

	local npcId = getNpcIdFromPrompt(prompt)
	if not npcId then return end

	-- Fire client to open UI; server will still validate content via DialogueRequest
	print("[NPCDialogueBinder] PromptTriggered -> DialogueEvent:", player.Name, "npcId:", npcId)
	DialogueEvent:FireClient(player, npcId)
end)
