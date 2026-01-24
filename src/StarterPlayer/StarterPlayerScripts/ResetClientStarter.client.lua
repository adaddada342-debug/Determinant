-- StarterPlayerScripts/ResetClientStarter.client.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Your client module
local ResetFX = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ResetFXClient"))

warn("[ResetClientStarter] ResetFXClient loaded. HoldToReset armed.")

ResetFX.HoldToReset({
	key = Enum.KeyCode.R,
	holdSeconds = 3.0,
	cinematicSeconds = 5.5,
	title = "RESET",
	subtitle = "Hold to overwrite timeline",
})
