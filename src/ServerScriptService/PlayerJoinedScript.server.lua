local ReplicatedStorage = game:GetService('ReplicatedStorage')
local remoteEvent = ReplicatedStorage:WaitForChild('JoinRemoteEvent')--Change this to the name of your "RemoteEvent"

local function onPlayerJoin(player)
	remoteEvent:FireAllClients(player.Name)
end

game.Players.PlayerAdded:Connect(onPlayerJoin)