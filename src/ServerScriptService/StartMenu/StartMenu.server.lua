-- ServerScriptService/StartMenu.server.lua
-- StartMenu is the ONLY authority that spawns the character initially.
-- FIXES:
-- ✅ Remotes are STABLE (no destroy/recreate). Prevents client listening to a dead RemoteEvent.
-- ✅ Ignores menu actions after GameStarted
-- ✅ ClientGameplayReady idempotent
-- ✅ Kills characters only while SpawnOwner=="StartMenu"
-- ✅ Debounced saves to reduce DS queue spam
-- ✅ NEW: Soul persistence per save slot (payload.soulType)
-- ✅ NEW: Client sends MenuAction "SetSoul" before ClientGameplayReady; server stores and sets player attribute SoulType

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")




Players.CharacterAutoLoads = false

-- =========================
-- Remotes (STABLE)
-- =========================
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
if not Remotes then
	Remotes = Instance.new("Folder")
	Remotes.Name = "Remotes"
	Remotes.Parent = ReplicatedStorage
end

local function getOrCreate(name, className)
	local r = Remotes:FindFirstChild(name)
	if not r then
		r = Instance.new(className)
		r.Name = name
		r.Parent = Remotes
	else
		if r.ClassName ~= className then
			warn(("[StartMenu] Remote %s is %s but expected %s. Fix in Studio.")
				:format(name, r.ClassName, className))
		end
	end
	return r
end

local MenuAction  = getOrCreate("MenuAction", "RemoteEvent")
local MenuCommand = getOrCreate("MenuCommand", "RemoteEvent")
local MenuState   = getOrCreate("MenuState", "RemoteFunction")

-- =========================
-- Data
-- =========================
local SaveStore = DataStoreService:GetDataStore("DETERMINANT_SAVES_V2")

local DEFAULT_SETTINGS = {
	masterVolume = 0.85,
	musicVolume  = 0.80,
	sfxVolume    = 0.85,
	uiScale = 1.0,
	graphicsQuality = 7,
	cameraShake = true,
	reducedFlashes = false,
	showDamageNumbers = true,
	bloodEffects = true,
}

local VALID_SOULS = {
	BRAVERY=true, JUSTICE=true, KINDNESS=true, PATIENCE=true, INTEGRITY=true, PERSEVERANCE=true,
}

local function deepCopy(t)
	local out = {}
	for k,v in pairs(t) do
		out[k] = (type(v) == "table") and deepCopy(v) or v
	end
	return out
end

local function defaultProfile()
	return {
		settings = deepCopy(DEFAULT_SETTINGS),
		slots = {
			[1] = { exists=false },
			[2] = { exists=false },
			[3] = { exists=false },
		},
	}
end

local function clampSettingsPatch(patch)
	local clean = {}
	for k,v in pairs(patch or {}) do
		if k == "masterVolume" or k == "musicVolume" or k == "sfxVolume" then
			clean[k] = math.clamp(tonumber(v) or DEFAULT_SETTINGS[k], 0, 1)
		elseif k == "uiScale" then
			clean[k] = math.clamp(tonumber(v) or DEFAULT_SETTINGS[k], 0.8, 1.2)
		elseif k == "graphicsQuality" then
			clean[k] = math.clamp(math.floor((tonumber(v) or DEFAULT_SETTINGS[k]) + 0.5), 1, 10)
		elseif k == "cameraShake" or k == "reducedFlashes" or k == "showDamageNumbers" or k == "bloodEffects" then
			clean[k] = (v == true)
		end
	end
	return clean
end

local function saveKey(userId) return ("u:%d"):format(userId) end

local function safeGetProfile(player)
	local key = saveKey(player.UserId)
	local ok, data = pcall(function()
		return SaveStore:GetAsync(key)
	end)

	if ok and type(data) == "table" then
		local prof = defaultProfile()
		if type(data.settings) == "table" then
			for k,v in pairs(data.settings) do prof.settings[k] = v end
		end
		if type(data.slots) == "table" then
			for i=1,3 do
				local s = data.slots[i]
				if type(s) == "table" then
					prof.slots[i] = {
						exists = (s.exists == true),
						slotName = s.slotName,
						updatedAt = s.updatedAt,
						payload = s.payload,
					}
				end
			end
		end
		return prof
	end

	return defaultProfile()
end

local function slotsSummary(prof)
	local out = {}
	for i=1,3 do
		local s = prof.slots[i] or {exists=false}
		out[i] = { exists = s.exists == true, slotName = s.slotName, updatedAt = s.updatedAt }
	end
	return out
end

-- =========================
-- Save debounce
-- =========================
local profileCache = {}
local pendingSave = {}     -- [player] = true
local SAVE_DEBOUNCE = 10

local function scheduleSave(player)
	if pendingSave[player] then return end
	pendingSave[player] = true

	task.delay(SAVE_DEBOUNCE, function()
		pendingSave[player] = nil
		if not player or not player.Parent then return end
		local prof = profileCache[player]
		if type(prof) ~= "table" then return end

		local key = saveKey(player.UserId)
		local ok, err = pcall(function()
			SaveStore:SetAsync(key, prof)
		end)
		if not ok then warn("[StartMenu] Save failed:", err) end
	end)
end

local function saveNow(player)
	if not player then return end
	local prof = profileCache[player]
	if type(prof) ~= "table" then return end
	local key = saveKey(player.UserId)
	pcall(function() SaveStore:SetAsync(key, prof) end)
end

-- =========================
-- Runtime state
-- =========================
local pendingStart = {} -- [player] = {reqId, slot, mode}
local starting = {}     -- [player] = true

local function isInMenu(player)
	return player:GetAttribute("InMenu") == true and player:GetAttribute("GameStarted") ~= true
end

local function sendEnterMenu(player)
	if not isInMenu(player) then return end
	local prof = profileCache[player]
	if not prof then return end
	MenuCommand:FireClient(player, "EnterMenu", {
		settings = prof.settings,
		slots = slotsSummary(prof),
	})
end

local function enterMenu(player)
	player:SetAttribute("InMenu", true)
	player:SetAttribute("GameStarted", false)
	player:SetAttribute("SpawnOwner", "StartMenu")
	player:SetAttribute("ActiveSaveSlot", nil)
	player:SetAttribute("SoulType", nil)

	if player.Character then
		player.Character:Destroy()
		player.Character = nil
	end
end

local function enforceNoCharacterWhileInMenu(player)
	player.CharacterAdded:Connect(function(char)
		task.defer(function()
			if not player.Parent or not char or not char.Parent then return end
			if player:GetAttribute("InMenu") == true and player:GetAttribute("SpawnOwner") == "StartMenu" then
				warn(("[StartMenu] Destroying character for %s (menu owns spawn)"):format(player.Name))
				char:Destroy()
			end
		end)
	end)
end

-- =========================
-- Slot ops
-- =========================
local function freshPayload()
	return { level = 1, xp = 0, flags = {}, createdAt = os.time(), soulType = nil }
end

local function doCreateOrOverwrite(player, slot)
	local prof = profileCache[player]
	if not prof then return false end
	prof.slots[slot] = {
		exists = true,
		slotName = ("Save %d"):format(slot),
		updatedAt = os.time(),
		payload = freshPayload(),
	}
	scheduleSave(player)
	return true
end

local function markPlayed(player, slot)
	local prof = profileCache[player]
	if not prof then return end
	local s = prof.slots[slot]
	if type(s) == "table" and s.exists then
		s.updatedAt = os.time()
		scheduleSave(player)
	end
end

local function getSlotSoulType(prof, slot)
	local s = prof and prof.slots and prof.slots[slot]
	local p = s and s.payload
	local st = p and p.soulType
	if type(st) == "string" and VALID_SOULS[st] then
		return st
	end
	return nil
end

local function startLoading(player, mode, slot, reqId)
	if not isInMenu(player) then
		return MenuCommand:FireClient(player, "Toast", { reqId=reqId, text="Menu not active." })
	end
	starting[player] = nil
	pendingStart[player] = { reqId=reqId, slot=slot, mode=mode }

	local prof = profileCache[player]
	local soulType = getSlotSoulType(prof, slot) -- send on Continue, or if already assigned

	MenuCommand:FireClient(player, "StartLoading", { reqId=reqId, slot=slot, mode=mode, soulType=soulType })
end

local function requestNewGame(player, slot, reqId)
	if not isInMenu(player) then return end
	local prof = profileCache[player]
	if not prof then return end

	slot = tonumber(slot)
	if not slot or slot < 1 or slot > 3 then
		return MenuCommand:FireClient(player, "Toast", { reqId=reqId, text="Invalid slot." })
	end

	local s = prof.slots[slot]
	if s and s.exists then
		return MenuCommand:FireClient(player, "ConfirmOverwrite", {
			reqId=reqId, slot=slot,
			title="Overwrite Save?",
			body=("Slot %d already has a save.\nStarting a new game will overwrite it.\n\nProceed?"):format(slot),
		})
	end

	startLoading(player, "NewGame", slot, reqId)
end

local function requestContinue(player, slot, reqId)
	if not isInMenu(player) then return end
	local prof = profileCache[player]
	if not prof then return end

	slot = tonumber(slot)
	if not slot or slot < 1 or slot > 3 then
		return MenuCommand:FireClient(player, "Toast", { reqId=reqId, text="Invalid slot." })
	end

	local s = prof.slots[slot]
	if not (s and s.exists) then
		return MenuCommand:FireClient(player, "Toast", { reqId=reqId, text=("Slot %d is empty."):format(slot) })
	end

	startLoading(player, "Continue", slot, reqId)
end

local function requestOverwrite(player, slot, reqId)
	if not isInMenu(player) then return end
	local prof = profileCache[player]
	if not prof then return end

	slot = tonumber(slot)
	if not slot or slot < 1 or slot > 3 then
		return MenuCommand:FireClient(player, "Toast", { reqId=reqId, text="Invalid slot." })
	end

	doCreateOrOverwrite(player, slot)
	MenuCommand:FireClient(player, "State", { slots = slotsSummary(prof) })
	startLoading(player, "NewGame", slot, reqId)
end

local function spawnIntoGame(player, reqId)
	local pend = pendingStart[player]
	if not pend or pend.reqId ~= reqId then
		warn(("[StartMenu] spawnIntoGame rejected for %s reqId=%s pend=%s")
			:format(player.Name, tostring(reqId), pend and tostring(pend.reqId) or "nil"))
		return MenuCommand:FireClient(player, "Toast", { reqId=reqId, text="Start expired. Try again." })
	end

	if starting[player] then return end
	starting[player] = true

	local slot = pend.slot
	local mode = pend.mode
	local prof = profileCache[player]
	if not prof then
		starting[player] = nil
		pendingStart[player] = nil
		return
	end

	if mode == "NewGame" then
		local s = prof.slots[slot]
		if not (s and s.exists) then
			doCreateOrOverwrite(player, slot)
			MenuCommand:FireClient(player, "State", { slots = slotsSummary(prof) })
		end
	end

	markPlayed(player, slot)

	-- Ensure SoulType attribute reflects saved slot
	local st = getSlotSoulType(prof, slot)
	player:SetAttribute("SoulType", st)

	player:SetAttribute("InMenu", false)
	player:SetAttribute("SpawnOwner", "Gameplay")
	player:SetAttribute("ActiveSaveSlot", slot)
	player:SetAttribute("GameStarted", true)

	pendingStart[player] = nil

	if player.Character then
		player.Character:Destroy()
		player.Character = nil
	end

	warn(("[StartMenu] LoadCharacter called for %s"):format(player.Name))
	player:LoadCharacter()

	local char = player.Character or player.CharacterAdded:Wait()
	warn(("[StartMenu] CharacterAdded received for %s: %s"):format(player.Name, char:GetFullName()))

	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 6)
	if not hum then
		starting[player] = nil
		return MenuCommand:FireClient(player, "Toast", { reqId=reqId, text="Spawn failed (no humanoid)." })
	end

	warn(("[StartMenu] Firing BeginGame to %s"):format(player.Name))
	MenuCommand:FireClient(player, "BeginGame", { reqId=reqId, slot=slot, mode=mode })

	starting[player] = nil
end

local function applySettings(player, patch, reqId)
	local prof = profileCache[player]
	if not prof then return end

	patch.reqId = nil
	patch.slot = nil

	local clean = clampSettingsPatch(patch)
	for k,v in pairs(clean) do prof.settings[k] = v end

	scheduleSave(player)
	MenuCommand:FireClient(player, "Settings", { reqId=reqId, settings=prof.settings })
end

local function applySoul(player, data)
	data = data or {}
	local reqId = tonumber(data.reqId)
	local slot = tonumber(data.slot)

	if not isInMenu(player) then return end
	if not reqId or not slot or slot < 1 or slot > 3 then return end

	local prof = profileCache[player]
	if not prof then return end

	-- Must match pending start reqId to prevent random spoofing
	local pend = pendingStart[player]
	if not pend or pend.reqId ~= reqId or pend.slot ~= slot then
		return
	end

	local soulType = tostring(data.soulType or "")
	if not VALID_SOULS[soulType] then
		return
	end

	local s = prof.slots[slot]
	if not (s and s.exists) then
		-- If NewGame slot wasn't created yet, don't silently create here (keep your existing flow).
		-- It will be created in spawnIntoGame, but we still store the soul in pending cache by attaching a temp payload.
		s = s or {}
		prof.slots[slot] = s
	end

	s.payload = s.payload or freshPayload()
	s.payload.soulType = soulType

	player:SetAttribute("SoulType", soulType)
	scheduleSave(player)
end

-- =========================
-- Player lifecycle
-- =========================
Players.PlayerAdded:Connect(function(player)
	profileCache[player] = safeGetProfile(player)
	enforceNoCharacterWhileInMenu(player)
	enterMenu(player)
	task.defer(function() sendEnterMenu(player) end)
end)

Players.PlayerRemoving:Connect(function(player)
	saveNow(player)
	profileCache[player] = nil
	pendingStart[player] = nil
	pendingSave[player] = nil
	starting[player] = nil
end)

MenuState.OnServerInvoke = function(player)
	local prof = profileCache[player] or safeGetProfile(player)
	profileCache[player] = prof
	if isInMenu(player) then
		sendEnterMenu(player)
	end
	return { settings = prof.settings, slots = slotsSummary(prof) }
end

-- =========================
-- MenuAction routing
-- =========================
MenuAction.OnServerEvent:Connect(function(player, action, data)
	data = data or {}
	local reqId = tonumber(data.reqId)

	if player:GetAttribute("GameStarted") == true and action ~= "RequestEnterMenu" then
		return
	end

	if action == "RequestEnterMenu" then
		return sendEnterMenu(player)
	end
	if action == "NewGame" then
		return requestNewGame(player, data.slot, reqId)
	end
	if action == "Continue" then
		return requestContinue(player, data.slot, reqId)
	end
	if action == "OverwriteSlot" then
		return requestOverwrite(player, data.slot, reqId)
	end
	if action == "SetSettings" then
		return applySettings(player, data, reqId)
	end

	-- ✅ NEW: receive assigned soul before gameplay ready
	if action == "SetSoul" then
		return applySoul(player, data)
	end

	if action == "ClientGameplayReady" then
		local pend = pendingStart[player]
		warn(("[StartMenu] ClientGameplayReady from %s reqId=%s pend=%s inMenu=%s gameStarted=%s starting=%s")
			:format(
				player.Name,
				tostring(reqId),
				pend and tostring(pend.reqId) or "nil",
				tostring(player:GetAttribute("InMenu")),
				tostring(player:GetAttribute("GameStarted")),
				tostring(starting[player] == true)
			))

		if starting[player] then return end

		if (not pend or pend.reqId ~= reqId) and isInMenu(player) then
			pendingStart[player] = { reqId=reqId, slot=1, mode="Forced" }
		end

		return spawnIntoGame(player, reqId)
	end
end)
