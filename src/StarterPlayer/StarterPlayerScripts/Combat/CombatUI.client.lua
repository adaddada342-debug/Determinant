-- StarterPlayerScripts/CombatUI.client.lua
-- Combat UI "headless" mode:
-- ✅ Keeps bridge + input + selection logic + events
-- ✅ Does NOT create any ScreenGui / Frames / TextLabels (no visual UI at all)
-- ✅ Still responds to Open/Close/Phase/HP/LV/KR/ActList/ItemList
-- ✅ Still fires Action / ActChosen / ItemChosen
-- NOTE: With no UI, mouse clicks obviously do nothing.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- =========================
-- SETTINGS
-- =========================
local AUTO_OPEN = false -- headless: default false (controller should call bridge:Fire("Open"))

-- =========================
-- Bridge (BindableEvent)
-- =========================
local BRIDGE_NAME = "__CombatUIBridge"
local bridge = playerGui:FindFirstChild(BRIDGE_NAME)
if not bridge then
	bridge = Instance.new("BindableEvent")
	bridge.Name = BRIDGE_NAME
	bridge.Parent = playerGui
end

-- =========================
-- Internal state (no GUI)
-- =========================
local enabled = false
local phase = "MENU" -- MENU | ENEMY | FIGHT_MINIGAME

local buttons = {
	{ key = "FIGHT" },
	{ key = "ACT" },
	{ key = "ITEM" },
	{ key = "MERCY" },
}
local selectedIndex = 1

local lv = 1
local hpCur, hpMax = 20, 20
local krCur, krMax = 0, 0

local actList = { "Check" }
local itemList = { "Bandage" }

-- Overlay/list selection (still works logically)
local overlayOpen = false
local listMode = nil -- "ACT" | "ITEM"
local listIndex = 1

-- =========================
-- Helpers
-- =========================
local function clampIndex(idx, n)
	if n <= 0 then return 1 end
	return ((idx - 1) % n) + 1
end

local function setSelected(index)
	selectedIndex = clampIndex(index, #buttons)
end

local function setListSelected(idx, entriesCount)
	entriesCount = entriesCount or 0
	if entriesCount <= 0 then
		listIndex = 1
		return
	end
	listIndex = clampIndex(idx, entriesCount)
end

-- =========================
-- Open/Close
-- =========================
local function openUI()
	enabled = true
	phase = "MENU"
	overlayOpen = false
	listMode = nil
	setSelected(1)
end

local function closeUI()
	overlayOpen = false
	listMode = nil
	enabled = false
end

-- =========================
-- Phase handling
-- =========================
local function setPhase(p)
	phase = p
	-- No visuals to update, but we keep the state.
end

-- =========================
-- Data setters
-- =========================
local function setHP(cur, max)
	hpCur = tonumber(cur) or 0
	hpMax = math.max(tonumber(max) or 1, 1)
end

local function setLV(v)
	lv = tonumber(v) or 1
end

local function setKR(cur, max)
	krCur = tonumber(cur) or 0
	krMax = math.max(tonumber(max) or 0, 0)
end

-- =========================
-- Overlay/list logic (headless)
-- =========================
local function openOverlay(mode)
	overlayOpen = true
	listMode = mode
	listIndex = 1
end

local function closeOverlay()
	overlayOpen = false
	listMode = nil
	listIndex = 1
end

local function currentEntries()
	if listMode == "ACT" then
		return actList
	elseif listMode == "ITEM" then
		return itemList
	end
	return nil
end

local function commitListChoice()
	local entries = currentEntries()
	if not entries or #entries == 0 then
		closeOverlay()
		return
	end
	local choice = tostring(entries[listIndex])
	closeOverlay()
	if listMode == "ACT" then
		bridge:Fire("ActChosen", choice)
	elseif listMode == "ITEM" then
		bridge:Fire("ItemChosen", choice)
	end
end

-- =========================
-- Input (Undertale-ish, headless)
-- =========================
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if not enabled then return end

	local kc = input.KeyCode

	-- Overlay nav (still functional logically)
	if overlayOpen then
		local entries = currentEntries()
		local n = entries and #entries or 0

		if kc == Enum.KeyCode.Up then
			setListSelected(listIndex - 1, n)
		elseif kc == Enum.KeyCode.Down then
			setListSelected(listIndex + 1, n)
		elseif kc == Enum.KeyCode.Z or kc == Enum.KeyCode.Return or kc == Enum.KeyCode.KeypadEnter then
			commitListChoice()
		elseif kc == Enum.KeyCode.X or kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.Backspace then
			closeOverlay()
		end
		return
	end

	-- Main menu nav
	if kc == Enum.KeyCode.Left then
		setSelected(selectedIndex - 1)
	elseif kc == Enum.KeyCode.Right then
		setSelected(selectedIndex + 1)
	elseif kc == Enum.KeyCode.Z or kc == Enum.KeyCode.Return or kc == Enum.KeyCode.KeypadEnter then
		local key = buttons[selectedIndex].key
		bridge:Fire("Action", key)

		if key == "ACT" then openOverlay("ACT") end
		if key == "ITEM" then openOverlay("ITEM") end
	elseif kc == Enum.KeyCode.X or kc == Enum.KeyCode.Escape or kc == Enum.KeyCode.Backspace then
		-- Back is intentionally left for your controller to interpret.
	end
end)

-- RenderStepped hook removed (it only existed to constantly reposition the heart)

-- =========================
-- Bridge receiver
-- =========================
bridge.Event:Connect(function(kind, a, b)
	if kind == "Open" then
		openUI()
	elseif kind == "Close" then
		closeUI()
	elseif kind == "Phase" then
		local p = tostring(a or "")
		if p == "MENU" or p == "ENEMY" or p == "FIGHT_MINIGAME" then
			setPhase(p)
		end
	elseif kind == "HP" then
		setHP(a, b)
	elseif kind == "LV" then
		setLV(a)
	elseif kind == "KR" then
		setKR(a, b)
	elseif kind == "ActList" then
		if typeof(a) == "table" and #a > 0 then actList = a end
	elseif kind == "ItemList" then
		if typeof(a) == "table" and #a > 0 then itemList = a end
	end
end)

-- Defaults (state only)
setLV(1)
setHP(20, 20)
setKR(0, 0)
setPhase("MENU")
setSelected(1)

if AUTO_OPEN then
	openUI()
end

print("[CombatUI] Loaded (HEADLESS). No GUI will be created. Bridge:", BRIDGE_NAME)
