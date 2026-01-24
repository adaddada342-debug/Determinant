-- ServerScriptService/Systems/DialogueBootstrap.server.lua (Script)
local ServerScriptService = game:GetService("ServerScriptService")

local systems = ServerScriptService:WaitForChild("Systems")
local DialogueService = require(systems:WaitForChild("DialogueService"))

DialogueService:BindRemotes()

print("[DialogueBootstrap] DialogueService bound remotes.")
