-- ServerScriptService/EnemyTagService
local CollectionService = game:GetService("CollectionService")

local ENEMY_TAG = "Enemy"

local function isEnemyModel(model: Instance): boolean
	if not model:IsA("Model") then return false end
	if model:FindFirstChildOfClass("Humanoid") == nil then return false end
	if model:GetAttribute("IsEnemy") == true then return true end
	if model.Parent and model.Parent:IsA("Folder") and model.Parent.Name == "Enemies" then return true end
	return false
end

local function tryTag(inst: Instance)
	if inst:IsA("Model") and isEnemyModel(inst) then
		if not CollectionService:HasTag(inst, ENEMY_TAG) then
			CollectionService:AddTag(inst, ENEMY_TAG)
		end
	end
end

-- Tag existing
for _, inst in ipairs(workspace:GetDescendants()) do
	tryTag(inst)
end

-- Tag future
workspace.DescendantAdded:Connect(function(inst)
	-- Humanoid might be added after model appears, so we re-check shortly
	task.defer(function()
		tryTag(inst)
		local m = inst:IsA("Model") and inst or inst:FindFirstAncestorOfClass("Model")
		if m then
			task.delay(0.25, function() tryTag(m) end)
			task.delay(1.0, function() tryTag(m) end)
		end
	end)
end)
