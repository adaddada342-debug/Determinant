-- ServerScriptService/InventoryServer.server.lua
-- Server-authoritative inventory snapshot + equip/unequip.
-- Items are Tools in Backpack or Character.
-- Tool Attributes used:
--   ItemType: "Weapon"/"Armor"/"Rune"/"Misc" (default Misc)
--   Rarity: string (optional)
--   Icon: rbxassetid string (optional)
--
-- FIXES:
--   ❌ Removed GetDebugId() (plugin capability error)
--   ✅ Adds stable per-tool UID via Attribute "InventoryUID" (GUID)
--   ✅ Supports Equip by uid (preferred) or name (fallback)
--   ✅ Pushes updates on add/remove + character spawn reliably

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- =========================================================
-- Remotes
-- =========================================================
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local InventoryRF = Remotes:FindFirstChild("InventoryRF")
if not InventoryRF then
	InventoryRF = Instance.new("RemoteFunction")
	InventoryRF.Name = "InventoryRF"
	InventoryRF.Parent = Remotes
end

local InventoryRE = Remotes:FindFirstChild("InventoryRE")
if not InventoryRE then
	InventoryRE = Instance.new("RemoteEvent")
	InventoryRE.Name = "InventoryRE"
	InventoryRE.Parent = Remotes
end

-- =========================================================
-- UID (stable tool identity)
-- =========================================================
local UID_ATTR = "InventoryUID"

local function getOrAssignUID(tool: Tool): string
	local uid = tool:GetAttribute(UID_ATTR)
	if typeof(uid) == "string" and uid ~= "" then
		return uid
	end
	uid = HttpService:GenerateGUID(false)
	tool:SetAttribute(UID_ATTR, uid)
	return uid
end

-- =========================================================
-- Helpers
-- =========================================================
local function getEquippedTool(character: Model?): Tool?
	if not character then return nil end
	return character:FindFirstChildOfClass("Tool")
end

local function toolInfo(tool: Tool, equippedTool: Tool?)
	-- Ensure uid exists server-side
	local uid = getOrAssignUID(tool)

	local itemType = tool:GetAttribute("ItemType") or "Misc"
	local rarity = tool:GetAttribute("Rarity") or "Common"
	local icon = tool:GetAttribute("Icon") or ""

	return {
		name = tool.Name,
		uid = uid,
		itemType = itemType,
		rarity = rarity,
		icon = icon,
		equipped = (equippedTool == tool),
	}
end

local function snapshot(player: Player)
	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	local equipped = getEquippedTool(character)
	local items = {}

	if character then
		for _, inst in ipairs(character:GetChildren()) do
			if inst:IsA("Tool") then
				table.insert(items, toolInfo(inst, equipped))
			end
		end
	end

	if backpack then
		for _, inst in ipairs(backpack:GetChildren()) do
			if inst:IsA("Tool") then
				table.insert(items, toolInfo(inst, equipped))
			end
		end
	end

	table.sort(items, function(a, b)
		if a.itemType ~= b.itemType then
			return tostring(a.itemType) < tostring(b.itemType)
		end
		if a.rarity ~= b.rarity then
			return tostring(a.rarity) < tostring(b.rarity)
		end
		return tostring(a.name) < tostring(b.name)
	end)

	return { items = items }
end

local function push(player: Player)
	InventoryRE:FireClient(player, snapshot(player))
end

local function findToolByUID(player: Player, uid: string): Tool?
	if typeof(uid) ~= "string" or uid == "" then return nil end

	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	local function scan(container: Instance?)
		if not container then return nil end
		for _, inst in ipairs(container:GetChildren()) do
			if inst:IsA("Tool") then
				local tUid = inst:GetAttribute(UID_ATTR)
				if tUid == uid then
					return inst
				end
			end
		end
		return nil
	end

	return scan(character) or scan(backpack)
end

local function findToolByName(player: Player, toolName: string): Tool?
	if typeof(toolName) ~= "string" or toolName == "" then return nil end

	local backpack = player:FindFirstChildOfClass("Backpack")
	local character = player.Character

	if character then
		local t = character:FindFirstChild(toolName)
		if t and t:IsA("Tool") then return t end
	end
	if backpack then
		local t = backpack:FindFirstChild(toolName)
		if t and t:IsA("Tool") then return t end
	end
	return nil
end

local function safeEquip(player: Player, payload)
	local character = player.Character
	if not character then return false, "no character" end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return false, "no humanoid" end
	if humanoid.Health <= 0 then return false, "dead" end

	local uid = payload and payload.uid
	local name = payload and payload.name

	local tool = nil :: Tool?
	if typeof(uid) == "string" and uid ~= "" then
		tool = findToolByUID(player, uid)
	end
	if not tool and typeof(name) == "string" and name ~= "" then
		tool = findToolByName(player, name)
	end
	if not tool then return false, "tool not found" end

	local equipped = getEquippedTool(character)
	if equipped == tool then
		humanoid:UnequipTools()
	else
		humanoid:EquipTool(tool)
	end

	return true
end

-- =========================================================
-- Live update wiring (no more “stale UI”)
-- =========================================================
local connections = {} :: {[Player]: {RBXScriptConnection}}

local function disconnectAll(player: Player)
	local conns = connections[player]
	if conns then
		for _, c in ipairs(conns) do
			c:Disconnect()
		end
	end
	connections[player] = nil
end

local function trackContainer(player: Player, container: Instance)
	-- Push when tools are added/removed or renamed
	local conns = connections[player]
	if not conns then return end

	table.insert(conns, container.ChildAdded:Connect(function(inst)
		if inst:IsA("Tool") then
			getOrAssignUID(inst)
			push(player)
		end
	end))

	table.insert(conns, container.ChildRemoved:Connect(function(inst)
		if inst:IsA("Tool") then
			push(player)
		end
	end))
end

local function setupPlayer(player: Player)
	disconnectAll(player)
	connections[player] = {}

	-- Backpack may exist before Character; track when it appears
	local function attachBackpack()
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			trackContainer(player, backpack)
			-- ensure UID on existing tools
			for _, t in ipairs(backpack:GetChildren()) do
				if t:IsA("Tool") then getOrAssignUID(t) end
			end
			push(player)
		end
	end

	attachBackpack()

	table.insert(connections[player], player.ChildAdded:Connect(function(inst)
		if inst:IsA("Backpack") then
			attachBackpack()
		end
	end))

	table.insert(connections[player], player.CharacterAdded:Connect(function(char)
		-- track tool changes in character = equipped changes
		task.defer(function()
			trackContainer(player, char)
			for _, t in ipairs(char:GetChildren()) do
				if t:IsA("Tool") then getOrAssignUID(t) end
			end
			push(player)
		end)
	end))

	-- If character already exists (respawn edge cases)
	if player.Character then
		task.defer(function()
			trackContainer(player, player.Character)
			for _, t in ipairs(player.Character:GetChildren()) do
				if t:IsA("Tool") then getOrAssignUID(t) end
			end
			push(player)
		end)
	end
end

Players.PlayerAdded:Connect(function(player)
	setupPlayer(player)
end)

Players.PlayerRemoving:Connect(function(player)
	disconnectAll(player)
end)

-- =========================================================
-- Remote API
-- =========================================================
InventoryRF.OnServerInvoke = function(player: Player, action: string, payload)
	if action == "Get" then
		return snapshot(player)
	end

	if action == "Equip" then
		local ok, why = safeEquip(player, payload)
		push(player)
		return { ok = ok, why = why }
	end

	return { ok = false, why = "unknown action" }
end
