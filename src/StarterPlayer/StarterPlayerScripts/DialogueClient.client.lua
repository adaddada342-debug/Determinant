-- StarterPlayerScripts/DialogueClient
-- Typewriter + silent choice reveal + keyboard navigation + ReplicatedStorage sounds
-- Now supports server-driven start via Remotes.DialogueEvent
-- Uses _G.__DialogueUIFX OpenAnim / CloseAnim / ImpactFlash if provided by DialogueGuiAutoSetup

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local DialogueRequest = remotes:WaitForChild("DialogueRequest")
local ResetRequest = remotes:WaitForChild("ResetRequest")
local DialogueEvent = remotes:WaitForChild("DialogueEvent") -- RemoteEvent (server says "open npcId")

local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("DialogueGui", 10)
assert(gui, "DialogueGui not found in PlayerGui. Ensure it's in StarterGui or created by DialogueGuiAutoSetup.")

local main = gui:WaitForChild("Main")
local npcNameLabel = main:WaitForChild("NpcName")
local textLabel = main:WaitForChild("Text")
local choicesFrame = main:WaitForChild("Choices")
local choiceTemplate = choicesFrame:WaitForChild("ChoiceTemplate")

-- ===== Sounds (ReplicatedStorage -> clone to SoundService) =====
local function ensureClientSounds()
	local existing = SoundService:FindFirstChild("UI_Sounds")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local src = ReplicatedStorage:FindFirstChild("UI_Sounds")
	if not (src and src:IsA("Folder")) then
		warn("[DialogueClient] UI_Sounds folder not found in ReplicatedStorage. Dialogue will work without sounds.")
		return nil
	end

	local cloned = src:Clone()
	cloned.Name = "UI_Sounds"
	cloned.Parent = SoundService
	return cloned
end

local soundsFolder = ensureClientSounds()
local SND_Back = soundsFolder and soundsFolder:FindFirstChild("Back") or nil
local SND_Move = soundsFolder and soundsFolder:FindFirstChild("Move") or nil
local SND_Select = soundsFolder and soundsFolder:FindFirstChild("Select") or nil
local SND_TextBlip = soundsFolder and soundsFolder:FindFirstChild("TextBlip") or nil

if SND_TextBlip then
	SND_TextBlip.Looped = false
end

local function playSound(snd: Sound?)
	if snd and snd:IsA("Sound") then
		snd:Stop()
		snd.TimePosition = 0
		snd:Play()
	end
end

local function stopBlip()
	if SND_TextBlip and SND_TextBlip:IsA("Sound") then
		SND_TextBlip:Stop()
		SND_TextBlip.TimePosition = 0
	end
end

-- ===== FX bridge =====
local function fx()
	return _G.__DialogueUIFX
end

local function fxOpen()
	local f = fx()
	if f and f.OpenAnim then
		f.OpenAnim()
	else
		main.Visible = true
	end
end

local function fxClose()
	local f = fx()
	if f and f.CloseAnim then
		f.CloseAnim()
	else
		main.Visible = false
	end
end

local function fxFlash(intensity: number?)
	local f = fx()
	if f and f.ImpactFlash then
		f.ImpactFlash(intensity)
	end
end

-- ===== State =====
local activeNpcId: string? = nil
local active = false

-- re-entry guard (prevents double-open spam from prompt retriggers)
local openToken = 0

-- typewriter control
local typing = false
local skipRequested = false
local typeToken = 0

-- keyboard choice selection
local choiceButtons: {TextButton} = {}
local choiceMeta = {} -- [btn] = { id = string, text = string }
local selectedIndex = 1
local keyboardArmed = false

-- tuning
local TYPE_DELAY = 0.018
local BLIP_EVERY = 2
local BLIP_MIN_GAP = 0.03
local lastBlipT = 0

local function clearChoices()
	for _, child in ipairs(choicesFrame:GetChildren()) do
		if child:IsA("TextButton") and child ~= choiceTemplate then
			child:Destroy()
		end
	end
	table.clear(choiceButtons)
	table.clear(choiceMeta)
	selectedIndex = 1
end

local function setChoicesVisible(visible: boolean)
	for _, btn in ipairs(choiceButtons) do
		btn.Visible = visible
	end
end

local function setSelected(idx: number, playMoveSound: boolean)
	if #choiceButtons == 0 then return end
	idx = math.clamp(idx, 1, #choiceButtons)

	for _, btn in ipairs(choiceButtons) do
		local sel = btn:FindFirstChild("Selector")
		if sel and sel:IsA("TextLabel") then
			sel.Visible = false
		end
	end

	selectedIndex = idx
	local cur = choiceButtons[selectedIndex]
	local sel = cur:FindFirstChild("Selector")
	if sel and sel:IsA("TextLabel") then
		sel.Visible = true
	end

	if playMoveSound then
		playSound(SND_Move)
	end
end

local function closeDialogue()
	active = false
	activeNpcId = nil
	typing = false
	skipRequested = false
	keyboardArmed = false
	typeToken += 1
	stopBlip()
	fxClose()
	playSound(SND_Back)
end

-- Typewriter: returns true when finished, false if cancelled
local function typewrite(fullText: string)
	typeToken += 1
	local myToken = typeToken

	typing = true
	skipRequested = false
	textLabel.Text = ""
	stopBlip()

	local visibleCount = 0

	for i = 1, #fullText do
		if myToken ~= typeToken then
			stopBlip()
			return false
		end
		if skipRequested then
			break
		end

		local ch = fullText:sub(i, i)
		textLabel.Text ..= ch

		if ch ~= " " and ch ~= "\n" and ch ~= "\t" then
			visibleCount += 1
			if (visibleCount % BLIP_EVERY) == 0 then
				local now = os.clock()
				if now - lastBlipT >= BLIP_MIN_GAP then
					playSound(SND_TextBlip)
					lastBlipT = now
				end
			end
		end

		task.wait(TYPE_DELAY)
	end

	if myToken == typeToken then
		textLabel.Text = fullText
		typing = false
		stopBlip()
		return true
	end

	stopBlip()
	return false
end

local function styleChoiceButton(btn: TextButton)
	local hoverArmed = false
	task.delay(0.15, function()
		hoverArmed = true
	end)

	btn.MouseEnter:Connect(function()
		if typing then return end

		-- mouse selects hovered option
		for i, b in ipairs(choiceButtons) do
			if b == btn then
				setSelected(i, hoverArmed and not keyboardArmed)
				break
			end
		end
	end)
end

-- Forward declare render so activateSelected can call it
local function render(packet: any) end

local function activateSelected()
	if typing then
		skipRequested = true
		return
	end
	if #choiceButtons == 0 then return end

	local btn = choiceButtons[selectedIndex]
	local meta = choiceMeta[btn]
	if not meta then return end

	if meta.id == "leave" then
		closeDialogue()
		return
	end

	playSound(SND_Select)
	fxFlash(0.55)

	local nextPacket = DialogueRequest:InvokeServer(activeNpcId, meta.id)
	render(nextPacket)
end

function render(packet: any)
	if not packet then
		warn("[DialogueClient] Got nil packet (memory not loaded / bad npcId).")
		closeDialogue()
		return
	end

	-- If dialogue was replaced while waiting on server, bail.
	if not active then return end

	npcNameLabel.Text = packet.name or "???"

	clearChoices()

	local choices = packet.choices or {}
	for i, c in ipairs(choices) do
		local btn = choiceTemplate:Clone()
		btn.Visible = false
		btn.Text = c.text or "..."
		if btn:FindFirstChild("Selector") then
			btn.Text = "  " .. btn.Text
		end
		btn.LayoutOrder = i
		btn.Parent = choicesFrame

		table.insert(choiceButtons, btn)
		choiceMeta[btn] = { id = c.id, text = c.text }

		styleChoiceButton(btn)

		btn.MouseButton1Click:Connect(function()
			if typing then
				skipRequested = true
				return
			end
			setSelected(i, false)

			if c.id == "leave" then
				closeDialogue()
				return
			end

			playSound(SND_Select)
			fxFlash(0.55)

			local nextPacket = DialogueRequest:InvokeServer(activeNpcId, c.id)
			render(nextPacket)
		end)
	end

	local fullText = packet.text or ""

	task.spawn(function()
		local finished = typewrite(fullText)
		if not active then return end
		if finished then
			setChoicesVisible(true)
			keyboardArmed = true
			setSelected(1, false)
		end
	end)
end

-- Public start (can still be used by other client code if needed)
_G.StartDialogue = function(npcId: any)
	if typeof(npcId) ~= "string" or npcId == "" then
		warn("[DialogueClient] StartDialogue invalid npcId:", npcId)
		return
	end

	openToken += 1
	local myOpen = openToken

	-- If already active with same npc, ignore
	if active and activeNpcId == npcId then
		return
	end

	activeNpcId = npcId
	active = true

	fxOpen()

	-- Fetch start packet
	local packet = DialogueRequest:InvokeServer(npcId, "start")

	-- If another open happened during invoke, ignore this one
	if myOpen ~= openToken then
		return
	end

	render(packet)
end

-- Server-driven dialogue start
DialogueEvent.OnClientEvent:Connect(function(npcId)
	_G.StartDialogue(npcId)
end)

-- Input
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end

	-- RESET hook stays as you had it
	if input.KeyCode == Enum.KeyCode.R then
		if _G.__ResetHoldBusy then return end
		_G.__ResetHoldBusy = true

		task.spawn(function()
			local ResetFX = require(ReplicatedStorage.Shared.ResetFXClient)
			local triggered = ResetFX.HoldToReset({
				key = Enum.KeyCode.R,
				holdSeconds = 3.0,
				title = "RESET",
				subtitle = "Hold to overwrite timeline",
				cinematicSeconds = 4.0,
			})

			if triggered then
				ResetRequest:FireServer()
				task.wait(0.8)
			end

			_G.__ResetHoldBusy = false
		end)

		return
	end

	if not active then return end

	-- Skip typewriter
	if input.KeyCode == Enum.KeyCode.Space then
		if typing then skipRequested = true end
		return
	end

	if input.KeyCode == Enum.KeyCode.Return then
		if typing then
			skipRequested = true
		else
			activateSelected()
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.Up then
		if not typing and #choiceButtons > 0 then
			keyboardArmed = true
			setSelected(selectedIndex - 1, true)
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.Down then
		if not typing and #choiceButtons > 0 then
			keyboardArmed = true
			setSelected(selectedIndex + 1, true)
		end
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		closeDialogue()
		return
	end
end)

textLabel.InputBegan:Connect(function()
	if active and typing then
		skipRequested = true
	end
end)

main.Visible = false
