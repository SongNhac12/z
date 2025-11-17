--=====================================================
--  ANTI AFK
--=====================================================
loadstring(game:HttpGet("https://raw.githubusercontent.com/Genesisuii/Genesisuii/refs/heads/main/Anti%20AFK%20script", true))()

local ReplicatedStorage = game:GetService("ReplicatedStorage")

--=====================================================
--  SHOP EVENTS
--=====================================================

local purchaseEventItem = ReplicatedStorage:WaitForChild("rbxts_include")
    :WaitForChild("node_modules")
    :WaitForChild("@rbxts")
    :WaitForChild("remo")
    :WaitForChild("src")
    :WaitForChild("container")
    :WaitForChild("shop.purchaseEventItem")

local purchaseGear = ReplicatedStorage:WaitForChild("rbxts_include")
    :WaitForChild("node_modules")
    :WaitForChild("@rbxts")
    :WaitForChild("remo")
    :WaitForChild("src")
    :WaitForChild("container")
    :WaitForChild("shop.purchaseGear")

local argsBait = { [1] = "baitpack:Atlantis" }
local argsFood = { [1] = "FoodScoop" }

--=====================================================
--  SCRIPT CONTROL
--=====================================================

_G.AutoShop = false
_G.AutoCraft = false

--=====================================================
--  AUTO CRAFT FUNCTION
--=====================================================
local function doCraft()
    if not _G.AutoCraft then return end

    -- 1) Select Craft Item
    local args = { "TimeJumper", "gear" }
    ReplicatedStorage.rbxts_include.node_modules["@rbxts"].remo.src.container["crafting.selectCraftingItem"]:FireServer(unpack(args))

    task.wait(0.5)

    -- 2) Submit Materials
    local args2 = {
        { "TeleportWand", "MagnifyingGlass", "AdvancedAutoFeeder" },
        "gear"
    }
    ReplicatedStorage.rbxts_include.node_modules["@rbxts"].remo.src.container["crafting.submitItems"]:FireServer(unpack(args2))

    task.wait(0.5)

    -- 3) Start Craft
    local args3 = { "gear" }
    ReplicatedStorage.rbxts_include.node_modules["@rbxts"].remo.src.container["crafting.startCraft"]:FireServer(unpack(args3))

    -- WAIT 10 MINUTES
    for i = 1, 600 do
        if not _G.AutoCraft then return end
        task.wait(1)
    end

    -- 4) Collect Craft
    local args4 = { "gear" }
    ReplicatedStorage.rbxts_include.node_modules["@rbxts"].remo.src.container["crafting.collectCraft"]:FireServer(unpack(args4))
end

--=====================================================
--  THREAD LOOPS
--=====================================================

task.spawn(function()
    while true do
        if _G.AutoShop then
            purchaseEventItem:FireServer(unpack(argsBait))
            purchaseGear:FireServer(unpack(argsFood))
        end
        task.wait(1)
    end
end)

task.spawn(function()
    while true do
        if _G.AutoCraft then
            doCraft()
        end
        task.wait(1)
    end
end)

--=====================================================
--  SIMPLE UI (DRAGGABLE)
--=====================================================

local ScreenGui = Instance.new("ScreenGui", game.CoreGui)
local Frame = Instance.new("Frame", ScreenGui)
local UICorner = Instance.new("UICorner", Frame)

Frame.Size = UDim2.new(0, 190, 0, 120)
Frame.Position = UDim2.new(0.05, 0, 0.3, 0)
Frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)

local dragToggle, dragStart, startPos

Frame.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragToggle = true
        dragStart = input.Position
        startPos = Frame.Position
    end
end)

Frame.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragToggle = false
    end
end)

game:GetService("UserInputService").InputChanged:Connect(function(input)
    if dragToggle and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        Frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

--=====================================================
--  BUTTONS
--=====================================================

local function createBtn(text, order)
    local btn = Instance.new("TextButton", Frame)
    btn.Size = UDim2.new(1, -20, 0, 40)
    btn.Position = UDim2.new(0, 10, 0, 10 + (order - 1) * 45)
    btn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 16
    btn.Text = text

    Instance.new("UICorner", btn)

    return btn
end

local shopBtn = createBtn("Auto Shop: OFF", 1)
local craftBtn = createBtn("Auto Craft: OFF", 2)

shopBtn.MouseButton1Click:Connect(function()
    _G.AutoShop = not _G.AutoShop
    shopBtn.Text = "Auto Shop: " .. (_G.AutoShop and "ON" or "OFF")
end)

craftBtn.MouseButton1Click:Connect(function()
    _G.AutoCraft = not _G.AutoCraft
    craftBtn.Text = "Auto Craft: " .. (_G.AutoCraft and "ON" or "OFF")
end)
