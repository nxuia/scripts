local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Camera = workspace.CurrentCamera
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- == CREDITS UI == --

local creditsGui = Instance.new("ScreenGui")
creditsGui.Name = "CreditsGUI"
creditsGui.ResetOnSpawn = false
creditsGui.IgnoreGuiInset = true
creditsGui.Parent = PlayerGui

local creditBox = Instance.new("Frame")
creditBox.Size = UDim2.new(0, 400, 0, 60)
creditBox.Position = UDim2.new(0.5, 0, 0.5, 0)
creditBox.AnchorPoint = Vector2.new(0.5, 0.5)
creditBox.BackgroundColor3 = Color3.new(0, 0, 0)
creditBox.BackgroundTransparency = 1
creditBox.Parent = creditsGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 20)
corner.Parent = creditBox

local creditText = Instance.new("TextLabel")
creditText.Size = UDim2.new(1, 0, 1, 0)
creditText.BackgroundTransparency = 1
creditText.Text = "Made by NIGGER"
creditText.Font = Enum.Font.GothamBold
creditText.TextScaled = true
creditText.TextColor3 = Color3.new(1, 1, 1)
creditText.TextStrokeTransparency = 1
creditText.TextStrokeColor3 = Color3.new(1, 1, 1)
creditText.TextTransparency = 1
creditText.Parent = creditBox

local function showCredits()
	TweenService:Create(creditBox, TweenInfo.new(1), {BackgroundTransparency = 0.2}):Play()
	TweenService:Create(creditText, TweenInfo.new(1), {
		TextTransparency = 0,
		TextStrokeTransparency = 0
	}):Play()
	task.wait(4)
	TweenService:Create(creditBox, TweenInfo.new(1), {BackgroundTransparency = 1}):Play()
	TweenService:Create(creditText, TweenInfo.new(1), {
		TextTransparency = 1,
		TextStrokeTransparency = 1
	}):Play()
end

-- == MINI CREDITS (Bottom Left Corner) == --
local miniCredits = Instance.new("TextLabel")
miniCredits.Size = UDim2.new(0, 180, 0, 24)
miniCredits.Position = UDim2.new(0, 10, 1, -30)
miniCredits.BackgroundTransparency = 1
miniCredits.Text = "made with <3 || discord.gg/2FKTaAHtCy"
miniCredits.Font = Enum.Font.GothamSemibold
miniCredits.TextSize = 14
miniCredits.TextColor3 = Color3.new(1, 1, 1)
miniCredits.TextXAlignment = Enum.TextXAlignment.Left
miniCredits.Parent = creditsGui

-- == AIMBOT (ESP Box Top Center + FOV Circle) == --

local AimEnabled = false
local Smoothness = getgenv().Smooth
local AimbotMode = "Legit"
local MaxFOV = 60

-- FOV Circle (mouse-following)
local fovCircle = Drawing.new("Circle")
fovCircle.Visible = true
fovCircle.Radius = MaxFOV
fovCircle.Thickness = 1
fovCircle.Position = Vector2.new(Mouse.X, Mouse.Y)
fovCircle.Transparency = 0
fovCircle.Color = Color3.fromRGB(255, 255, 255)
fovCircle.Filled = false

-- Static Center FOV Circle
local centerFOVCircle = Drawing.new("Circle")
centerFOVCircle.Visible = true
centerFOVCircle.Radius = MaxFOV
centerFOVCircle.Thickness = 1
centerFOVCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
centerFOVCircle.Transparency = 1
centerFOVCircle.Color = Color3.fromRGB(255, 255, 255)
centerFOVCircle.Filled = false

local function updateFOV()
	fovCircle.Position = Vector2.new(Mouse.X, Mouse.Y)
	centerFOVCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
end

local function getESPBoxTopCenter(player)
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return nil end

	local parts = {}
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			table.insert(parts, part)
		end
	end

	local top = nil
	for _, part in ipairs(parts) do
		if not top or part.Position.Y > top.Y then
			top = part.Position
		end
	end

	if not top then return nil end

	local screenPos, onScreen = Camera:WorldToScreenPoint(top)
	if not onScreen then return nil end

	local unitRay = Camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	return unitRay.Origin + unitRay.Direction * 1000
end

local function aimAtTarget()
	local targetPos = nil
	local shortest = MaxFOV

	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= LocalPlayer and player.Character then
			local target = getESPBoxTopCenter(player)
			if target then
				local screenPos, onScreen = Camera:WorldToScreenPoint(target)
				if onScreen then
					local dist = (Vector2.new(Mouse.X, Mouse.Y) - Vector2.new(screenPos.X, screenPos.Y)).Magnitude
					if dist < shortest then
						shortest = dist
						targetPos = target
					end
				end
			end
		end
	end

	if targetPos then
		local camPos = Camera.CFrame.Position
		local aimCFrame = CFrame.new(camPos, targetPos)
		if AimbotMode == "Instant" then
			Camera.CFrame = aimCFrame
		else
			Camera.CFrame = Camera.CFrame:Lerp(aimCFrame, Smoothness)
		end
	end
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.UserInputType == Enum.UserInputType.MouseButton2 then
		AimEnabled = true
	end
end)

UserInputService.InputEnded:Connect(function(input, processed)
	if input.UserInputType == Enum.UserInputType.MouseButton2 then
		AimEnabled = false
	end
end)

RunService.RenderStepped:Connect(function()
	updateFOV()
	if AimEnabled then
		aimAtTarget()
	end
end)

-- == WHITE BOX ESP + NAME == --

local ESPObjects = {}

local function removeESP(player)
	local esp = ESPObjects[player]
	if esp then
		if esp.Box then esp.Box:Remove() end
		if esp.Name then esp.Name:Remove() end
		ESPObjects[player] = nil
	end
end

local function createESP(player)
	if player == LocalPlayer then return end

	removeESP(player)

	local box = Drawing.new("Square")
	box.Thickness = 1
	box.Filled = false
	box.Color = Color3.fromRGB(255, 255, 255)
	box.Transparency = 1
	box.Visible = false

	local nameTag = Drawing.new("Text")
	nameTag.Size = 14
	nameTag.Center = true
	nameTag.Outline = true
	nameTag.Color = Color3.fromRGB(255, 255, 255)
	nameTag.Text = player.Name
	nameTag.Visible = false

	ESPObjects[player] = {
		Box = box,
		Name = nameTag,
	}

	player.CharacterAdded:Connect(function()
		task.wait(1)
		createESP(player)
	end)

	player.CharacterRemoving:Connect(function()
		removeESP(player)
	end)

	if player.Character then
		local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Died:Connect(function()
				removeESP(player)
			end)
		end
	end
end

local function getCharacterBounds(character)
	local parts = {}
	for _, part in ipairs(character:GetChildren()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			table.insert(parts, part)
		end
	end

	local top, bottom = nil, nil
	for _, part in ipairs(parts) do
		if not top or part.Position.Y > top.Y then top = part.Position end
		if not bottom or part.Position.Y < bottom.Y then bottom = part.Position end
	end

	return top, bottom
end

RunService.RenderStepped:Connect(function()
	for player, esp in pairs(ESPObjects) do
		local character = player.Character
		if character and character:FindFirstChild("HumanoidRootPart") then
			local top, bottom = getCharacterBounds(character)
			if not top or not bottom then continue end

			local topScreen, topOnScreen = Camera:WorldToViewportPoint(top)
			local bottomScreen, bottomOnScreen = Camera:WorldToViewportPoint(bottom)

			if topOnScreen and bottomOnScreen then
				local height = math.abs(topScreen.Y - bottomScreen.Y)
				local width = height / 2
				local centerX = (topScreen.X + bottomScreen.X) / 2

				esp.Box.Size = Vector2.new(width, height)
				esp.Box.Position = Vector2.new(centerX - width / 2, topScreen.Y)
				esp.Box.Visible = true

				esp.Name.Text = player.Name
				esp.Name.Position = Vector2.new(centerX, topScreen.Y - 16)
				esp.Name.Visible = true
			else
				esp.Box.Visible = false
				esp.Name.Visible = false
			end
		else
			if esp then
				esp.Box.Visible = false
				esp.Name.Visible = false
			end
		end
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	if player ~= LocalPlayer then
		createESP(player)
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		createESP(player)
	end)
end)

Players.PlayerRemoving:Connect(removeESP)
