-- ServerScriptService/InventorySync.server.lua
-- Production inventory replication: Snapshot + Delta updates, stable ItemId, watched stat attributes.
-- FIXES:
--   ✅ Name changes now replicate (GetPropertyChangedSignal("Name"))
--   ✅ Uses AttributeChanged only for attributes (correct)
--   ✅ Avoids Luau type annotations (compat-safe)
--   ✅ Cleans up per-tool watchers safely

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local InventoryRF = Remotes:FindFirstChild("InventoryRF") or Instance.new("RemoteFunction")
InventoryRF.Name = "InventoryRF"
InventoryRF.Parent = Remotes

local InventoryRE = Remotes:FindFirstChild("InventoryRE") or Instance.new("RemoteEvent")
InventoryRE.Name = "InventoryRE"
InventoryRE.Parent = Remotes

-- =========================
-- CONFIG: Which attributes you want to replicate for weapons
-- =========================
local WATCHED_ATTRS = {
	"Damage",
	"Speed",
	"CritChance",
	"CritDamage",
	"Range",
	"Weight",
	"Durability",
	"LevelReq",

	-- visuals / meta
	"ItemType", -- Weapon/Armor/Rune/Misc
	"Rarity",
	"Icon",
	"Description",
}

local DEFAULTS = {
	ItemType = "Misc",
	Rarity = "Common",
	Icon = "",
	Description = "",
}

local function isTool(inst)
	return inst and inst:IsA("Tool")
end

local function getEquippedTool(character)
	if not character then return nil end
	return character:FindFirstChildOfClass("Tool")
end

local function ensureItemId(tool)
	local id = tool:GetAttribute("ItemId")
	if typeof(id) ~= "string" or id == "" then
		id = HttpService:GenerateGUID(false)
		tool:SetAttribute("ItemId", id)
	end
	return id
end

local function readAttrs(tool)
	local attrs = {}
	for _, key in ipairs(WATCHED_ATTRS) do
		local v = tool:GetAttribute(key)
		if v == nil then
			v = DEFAULTS[key]
		end
		attrs[key] = v
	end
	return attrs
end

local function toolPacket(tool, equippedTool)
	local itemId = ensureItemId(tool)
	local attrs = readAttrs(tool)

	return {
		itemId = itemId,
		name = tool.Name,
		equipped = (equippedTool == tool),
		attrs = attrs,
	}
end

local function snapshot(player)
	local items = {}
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character
	local equipped = getEquippedTool(character)

	if character then
		for _, inst in ipairs(character:GetChildren()) do
			if isTool(inst) then
				table.insert(items, toolPacket(inst, equipped))
			end
		end
	end

	if backpack then
		for _, inst in ipairs(backpack:GetChildren()) do
			if isTool(inst) then
				table.insert(items, toolPacket(inst, equipped))
			end
		end
	end

	table.sort(items, function(a, b)
		local at = tostring(a.attrs.ItemType)
		local bt = tostring(b.attrs.ItemType)
		if at ~= bt then return at < bt end
		local ar = tostring(a.attrs.Rarity)
		local br = tostring(b.attrs.Rarity)
		if ar ~= br then return ar < br end
		return tostring(a.name) < tostring(b.name)
	end)

	return { items = items }
end

-- =========================
-- Per-player connections
-- =========================
local connectionsByPlayer = {}       -- [player] = {RBXScriptConnection...}
local toolAttrConnsByPlayer = {}     -- [player] = [itemId] = {conn...}

local function disconnectAll(player)
	local list = connectionsByPlayer[player]
	if list then
		for _, c in ipairs(list) do pcall(function() c:Disconnect() end) end
	end
	connectionsByPlayer[player] = nil

	local map = toolAttrConnsByPlayer[player]
	if map then
		for _, conns in pairs(map) do
			for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
		end
	end
	toolAttrConnsByPlayer[player] = nil
end

local function fireDelta(player, deltaType, payload)
	InventoryRE:FireClient(player, {
		type = deltaType, -- "Snapshot" | "Upsert" | "Remove" | "EquipState"
		payload = payload
	})
end

local function watchTool(player, tool)
	local itemId = ensureItemId(tool)
	toolAttrConnsByPlayer[player] = toolAttrConnsByPlayer[player] or {}
	if toolAttrConnsByPlayer[player][itemId] then return end

	local conns = {}
	toolAttrConnsByPlayer[player][itemId] = conns

	-- Initial upsert
	fireDelta(player, "Upsert", toolPacket(tool, getEquippedTool(player.Character)))

	-- Attribute updates (real attributes only)
	table.insert(conns, tool.AttributeChanged:Connect(function(attrName)
		if attrName == "ItemId" then return end
		for _, k in ipairs(WATCHED_ATTRS) do
			if k == attrName then
				fireDelta(player, "Upsert", toolPacket(tool, getEquippedTool(player.Character)))
				return
			end
		end
	end))

	-- Name changes (property, not attribute)
	table.insert(conns, tool:GetPropertyChangedSignal("Name"):Connect(function()
		fireDelta(player, "Upsert", toolPacket(tool, getEquippedTool(player.Character)))
	end))

	-- Tool removed/destroyed
	table.insert(conns, tool.Destroying:Connect(function()
		fireDelta(player, "Remove", { itemId = itemId })
		if toolAttrConnsByPlayer[player] then
			toolAttrConnsByPlayer[player][itemId] = nil
		end
	end))
end

local function rescan(player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	if character then
		for _, inst in ipairs(character:GetChildren()) do
			if isTool(inst) then watchTool(player, inst) end
		end
	end
	if backpack then
		for _, inst in ipairs(backpack:GetChildren()) do
			if isTool(inst) then watchTool(player, inst) end
		end
	end
end

local function hookContainer(player, container)
	connectionsByPlayer[player] = connectionsByPlayer[player] or {}
	local conns = connectionsByPlayer[player]

	table.insert(conns, container.ChildAdded:Connect(function(child)
		if isTool(child) then
			watchTool(player, child)
			fireDelta(player, "EquipState", snapshot(player))
		end
	end))

	table.insert(conns, container.ChildRemoved:Connect(function(child)
		if isTool(child) then
			local id = child:GetAttribute("ItemId")
			if typeof(id) == "string" then
				fireDelta(player, "Remove", { itemId = id })
			end
			fireDelta(player, "EquipState", snapshot(player))
		end
	end))
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function(char)
		task.defer(function()
			disconnectAll(player)
			connectionsByPlayer[player] = {}
			toolAttrConnsByPlayer[player] = {}

			local backpack = player:WaitForChild("Backpack")
			hookContainer(player, backpack)
			hookContainer(player, char)

			rescan(player)
			fireDelta(player, "Snapshot", snapshot(player))
		end)
	end)
end)

Players.PlayerRemoving:Connect(function(player)
	disconnectAll(player)
end)

-- =========================
-- RemoteFunction API
-- =========================
local function findToolByItemId(player, itemId)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local char = player.Character

	local function scan(container)
		if not container then return nil end
		for _, inst in ipairs(container:GetChildren()) do
			if isTool(inst) and inst:GetAttribute("ItemId") == itemId then
				return inst
			end
		end
		return nil
	end

	return scan(char) or scan(backpack)
end

InventoryRF.OnServerInvoke = function(player, action, payload)
	if action == "Get" then
		return snapshot(player)
	end

	if action == "Equip" then
		local itemId = payload and payload.itemId
		if typeof(itemId) ~= "string" then
			return { ok = false, why = "bad itemId" }
		end

		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not hum then return { ok = false, why = "no humanoid" } end

		local tool = findToolByItemId(player, itemId)
		if not tool then return { ok = false, why = "tool missing" } end

		local equipped = getEquippedTool(char)
		if equipped == tool then
			hum:UnequipTools()
		else
			hum:EquipTool(tool)
		end

		fireDelta(player, "Snapshot", snapshot(player))
		return { ok = true }
	end

	return { ok = false, why = "unknown action" }
end
