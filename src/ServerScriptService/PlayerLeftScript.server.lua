local ReplicatedStorage = game:GetService('ReplicatedStorage')
local remoteEvent = ReplicatedStorage:WaitForChild('LeaveRemoteEvent')--Change this to the name of your "RemoteEvent"

local function onPlayerLeave(player)
	remoteEvent:FireAllClients(player.Name)
end

game.Players.PlayerRemoving:Connect(onPlayerLeave)