local ReplicatedStorage = game:GetService('ReplicatedStorage')
local remoteEvent = ReplicatedStorage:WaitForChild('LeaveRemoteEvent')--Change this to the name of you "RemoteEvent"

textColor = Color3.new(1, 0, 0)

local function welcome(playerName)
	game.StarterGui:SetCore('ChatMakeSystemMessage', {
		Text = playerName..' has left the game';--You can change the message to whatever you want it to say
		Font = Enum.Font.FredokaOne; --This is the font or writing style of the message
		Color = textColor;
		FontSize = Enum.FontSize.Size24;--The size doesn't really matter but you can chage this too
	})
end

remoteEvent.OnClientEvent:Connect(welcome)