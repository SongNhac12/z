-- BananaHub v7 | Thuần Lua + chỉ nhặt trái từ Quake trở xuống + cất trái ngay

local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local isTeleporting = false
local isCollecting = false

local request = syn and syn.request or http_request or request or (fluxus and fluxus.request)

local MyTeam = {
    "Acc_01", "Acc_02",
}

-- ================= CONFIG =================
local MIN_TARGET = 1           -- số người tối thiểu của server đích
local MAX_TARGET = 2           -- số người tối đa của server đích
local MAX_PAGES = 5            -- số trang quét tối đa mỗi lần hop
local VISITED_TTL = 30 * 60    -- nhớ server đã vào trong 30 phút
local VISITED_FILE = "bananahub_visited.json"

local FLY_SPEED = 100          -- tốc độ bay tới trái (studs/giây)
local COLLECT_TIMEOUT = 30     -- tối đa bao nhiêu giây cho 1 trái

local AUTO_TEAM = true         -- tự chọn team khi mới vào
local TEAM_NAME = "Marines"    -- "Marines" hoặc "Pirates"

local STORE_RETRIES = 2        -- số vòng thử cất mỗi trái (mỗi vòng thử mọi kiểu tên)
local STORE_RETRY_DELAY = 5    -- cất lỗi: thử lại 1 lần sau chừng này giây (chạy nền)
local HOP_WAIT_STORE = 3       -- tối đa chờ cất xong trước khi hop (giây)
local SETTLE_TIME = 6          -- chờ map load & quét trái/factory khi mới vào server (giây)

-- Chỉ nhặt các trái trong danh sách này (từ Quake trở xuống theo bảng trái)
local ALLOWED_FRUITS = {
    "Quake", "Buddha", "Love", "Creation", "Spider", "Sound", "Phoenix",
    "Portal", "Lightning", "Pain", "Blizzard", "Gravity", "Mammoth",
    "T-Rex", "Dough", "Shadow", "Venom", "Gas", "Spirit",
    "Tiger", "Yeti", "Magnet", "Kitsune", "Control", "Dragon",
}

-- Trái không đọc được tên (vd chỉ ghi "Fruit"): true = vẫn đi nhặt, false = bỏ qua
local PICK_UNKNOWN = true
-- ==========================================

-- Các trái khác (để nhận ra tên và hiện "Bỏ qua: ..." cho dễ biết)
local OTHER_FRUITS = {
    "Diamond", "Light", "Rubber", "Ghost", "Magma",
    "Bomb", "Spike", "Chop", "Spring", "Kilo", "Smoke", "Spin", "Flame",
    "Falcon", "Ice", "Sand", "Dark", "Eagle", "Rocket", "Blade", "String",
    "Barrier", "Revive", "Door", "Paw", "Soul", "Rumble", "Leopard",
}

-- ================= NHẬN DIỆN TÊN TRÁI =================
local function normalize(s)
    s = string.lower(s)
    s = string.gsub(s, "[^a-z]", "")
    s = string.gsub(s, "fruit$", "")
    return s
end

local DISPLAY = {}      -- key -> tên hiển thị
local KEY_EXACT = {}    -- key hoặc key..key (vd "quakequake") -> tên hiển thị
local SORTED_KEYS = {}  -- key, dài trước
local ALLOWED_SET = {}  -- tên hiển thị được phép nhặt

local function register(display, allowed)
    local k = normalize(display)
    DISPLAY[k] = display
    KEY_EXACT[k] = display
    KEY_EXACT[k .. k] = display
    table.insert(SORTED_KEYS, k)
    if allowed then
        ALLOWED_SET[display] = true
    end
end

for _, n in ipairs(OTHER_FRUITS) do register(n, false) end
for _, n in ipairs(ALLOWED_FRUITS) do register(n, true) end
table.sort(SORTED_KEYS, function(a, b) return #a > #b end)

local function matchName(strings, allowPrefix)
    -- Khớp chính xác trước
    for _, s in ipairs(strings) do
        local c = normalize(s)
        if c ~= "" and KEY_EXACT[c] then
            return KEY_EXACT[c]
        end
    end

    -- Khớp đầu chuỗi (chỉ dùng cho tên/attribute của trái)
    if allowPrefix then
        for _, s in ipairs(strings) do
            local c = normalize(s)
            if c ~= "" then
                for _, k in ipairs(SORTED_KEYS) do
                    if #c > #k and string.sub(c, 1, #k) == k then
                        return DISPLAY[k]
                    end
                end
            end
        end
    end

    return nil
end

local nameCache = setmetatable({}, {__mode = "k"})

-- Trả về tên trái (vd "Quake") hoặc nil nếu không đọc được
local function identifyFruit(fruit)
    if nameCache[fruit] then return nameCache[fruit] end

    -- Bước 1: tên model + attribute
    local s1 = {fruit.Name}
    pcall(function()
        for _, a in pairs(fruit:GetAttributes()) do
            if type(a) == "string" then
                table.insert(s1, a)
            end
        end
    end)

    local name = matchName(s1, true)

    -- Bước 2: tên/chữ của các phần con
    if not name then
        local s2, n = {}, 0
        for _, d in ipairs(fruit:GetDescendants()) do
            n = n + 1
            if n > 80 then break end
            table.insert(s2, d.Name)
            if d:IsA("TextLabel") or d:IsA("TextButton") then
                table.insert(s2, d.Text)
            end
            if d:IsA("StringValue") then
                table.insert(s2, d.Value)
            end
        end
        name = matchName(s2, false)
    end

    if name then
        nameCache[fruit] = name
    end

    return name
end

-- ================= NHỚ SERVER ĐÃ VÀO =================
local visited = {}
pcall(function()
    if isfile and isfile(VISITED_FILE) then
        visited = HttpService:JSONDecode(readfile(VISITED_FILE))
    end
end)

local function saveVisited()
    pcall(function()
        if writefile then
            writefile(VISITED_FILE, HttpService:JSONEncode(visited))
        end
    end)
end

do
    local now = os.time()
    for id, t in pairs(visited) do
        if now - t > VISITED_TTL then
            visited[id] = nil
        end
    end
    visited[game.JobId] = now
    saveVisited()
end

-- ================= GUI =================
if CoreGui:FindFirstChild("BananaHub_v2") then CoreGui.BananaHub_v2:Destroy() end
local ScreenGui = Instance.new("ScreenGui", CoreGui)
ScreenGui.Name = "BananaHub_v2"

local Frame = Instance.new("Frame", ScreenGui)
Frame.Size = UDim2.new(0, 280, 0, 180)
Frame.Position = UDim2.new(0.5, -140, 0.05, 0)
Frame.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 8)

local function createLabel(text, pos, color)
    local lbl = Instance.new("TextLabel", Frame)
    lbl.Size = UDim2.new(1, -20, 0, 25)
    lbl.Position = pos
    lbl.Text = text
    lbl.TextColor3 = color or Color3.fromRGB(255, 255, 255)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 12
    return lbl
end

local Title = createLabel("SongNhacVJP", UDim2.new(0, 10, 0, 10), Color3.fromRGB(255, 200, 0))
local Status = createLabel("🛰️ Trạng thái: Đang quét...", UDim2.new(0, 10, 0, 45))
local FruitStatus = createLabel("🍎 Trái: Đang kiểm tra...", UDim2.new(0, 10, 0, 75))
local FactoryStatus = createLabel("🏭 Factory: Đang kiểm tra...", UDim2.new(0, 10, 0, 105))
local TimerLabel = createLabel("⏱️ Uptime: 0s", UDim2.new(0, 10, 0, 135), Color3.fromRGB(150, 150, 150))

-- ================= AUTO CHỌN TEAM =================
local function chooseTeam()
    if not AUTO_TEAM then return end

    local deadline = tick() + 30

    while tick() < deadline do
        -- Đã có team rồi thì thôi (không đổi team)
        if LocalPlayer.Team ~= nil then
            return true
        end

        Status.Text = "🏴 Đang chọn team " .. TEAM_NAME .. "..."
        Status.TextColor3 = Color3.fromRGB(0, 200, 255)

        -- Cách 1: gọi remote trực tiếp
        pcall(function()
            ReplicatedStorage.Remotes.CommF_:InvokeServer("SetTeam", TEAM_NAME)
        end)

        task.wait(1)

        -- Cách 2 (dự phòng): bấm nút trong menu chọn team
        if LocalPlayer.Team == nil then
            pcall(function()
                local main = LocalPlayer.PlayerGui:FindFirstChild("Main")
                local choose = main and main:FindFirstChild("ChooseTeam")
                local btn = choose
                    and choose.Container[TEAM_NAME].Frame.TextButton
                if btn and firesignal then
                    firesignal(btn.Activated)
                    firesignal(btn.MouseButton1Click)
                end
            end)
            task.wait(1)
        end
    end

    return LocalPlayer.Team ~= nil
end

-- ================= STORE FRUIT (cất ngay khi nhặt) =================
local totalStored = 0
local lastStoreResult = ""
local storingTools = setmetatable({}, {__mode = "k"}) -- tool đang được cất
local storeFailed = setmetatable({}, {__mode = "k"})  -- tool cất lỗi (không thử liên tục)
local storeRetried = setmetatable({}, {__mode = "k"}) -- tool đã được thử lại nền

local function isFruitTool(v)
    if not v:IsA("Tool") then return false end
    if string.find(v.Name:lower(), "fruit") then return true end
    if v.ToolTip == "Blox Fruit" then return true end
    if v:FindFirstChild("Fruit") then return true end
    return false
end

local function isHeld(tool)
    return tool.Parent == LocalPlayer.Backpack
        or (LocalPlayer.Character ~= nil and tool.Parent == LocalPlayer.Character)
end

-- Danh sách trái đang cầm trên người (Backpack + Character)
local function getHeldFruits()
    local list = {}
    for _, container in ipairs({LocalPlayer.Backpack, LocalPlayer.Character}) do
        if container then
            for _, v in ipairs(container:GetChildren()) do
                if isFruitTool(v) then
                    table.insert(list, v)
                end
            end
        end
    end
    return list
end

-- Có trái đang cầm mà cất lỗi (game không cho cầm thêm trái khác)
local function hasStuckFruit()
    for _, v in ipairs(getHeldFruits()) do
        if storeFailed[v] then
            return true
        end
    end
    return false
end

-- Các kiểu tên có thể dùng cho remote StoreFruit
-- Tool tên "Quake Fruit" -> tên nội bộ thường là "Quake-Quake"
local function getStoreNames(tool)
    local names, seen = {}, {}

    local function add(n)
        if type(n) == "string" and n ~= "" and not seen[n] then
            seen[n] = true
            table.insert(names, n)
        end
    end

    add(tool:GetAttribute("OriginalName"))
    add(tool:GetAttribute("FruitName"))

    if string.find(tool.Name, "%-") then
        add(tool.Name)
    end

    local base = (tool.Name:gsub("%s*[Ff]ruit%s*$", ""))
    base = (base:gsub("^%s+", ""))
    base = (base:gsub("%s+$", ""))

    if base ~= "" then
        add(base .. "-" .. base)
        add(base)
    end

    add(tool.Name)

    return names
end

-- Gọi remote 1 lần, trả về true nếu trái đã rời khỏi người
local function tryStoreOnce(tool, nameArg)
    local ok, res = pcall(function()
        return ReplicatedStorage.Remotes.CommF_:InvokeServer("StoreFruit", nameArg, tool)
    end)
    -- Ghi lại kết quả server trả về + tên đã thử để biết vì sao lỗi
    lastStoreResult = (ok and tostring(res) or ("lỗi: " .. tostring(res))) .. " [" .. nameArg .. "]"
    task.wait(0.25)
    return not isHeld(tool)
end

-- Thử cất bằng tất cả kiểu tên có thể
local function attemptStore(tool)
    -- Bỏ cầm trái trên tay trước khi cất
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and tool.Parent == char then
        pcall(function() hum:UnequipTools() end)
        task.wait(0.15)
    end

    local names = getStoreNames(tool)

    for _ = 1, STORE_RETRIES do
        for _, n in ipairs(names) do
            if not isHeld(tool) then return true end
            if tryStoreOnce(tool, n) then return true end
        end
    end

    return not isHeld(tool)
end

local function storeTool(tool)
    if storingTools[tool] or storeFailed[tool] then return false end
    storingTools[tool] = true

    local done = attemptStore(tool)

    storingTools[tool] = nil

    if done then
        totalStored = totalStored + 1
        FruitStatus.Text = "📦 Đã cất " .. totalStored .. " trái"
        FruitStatus.TextColor3 = Color3.fromRGB(0, 255, 100)
    else
        -- Cất lỗi: đánh dấu để không thử liên tục, thử lại 1 lần ở nền
        storeFailed[tool] = true
        FruitStatus.Text = "⚠️ Cất lỗi: " .. string.sub(lastStoreResult, 1, 34)
        FruitStatus.TextColor3 = Color3.fromRGB(255, 150, 0)

        if not storeRetried[tool] then
            storeRetried[tool] = true
            task.delay(STORE_RETRY_DELAY, function()
                if tool.Parent and isHeld(tool) then
                    storeFailed[tool] = nil
                    storeTool(tool)
                end
            end)
        end
    end

    return done
end

-- Quét và cất trái trên người (bỏ qua trái đang cất / đã lỗi)
-- Trả về số trái còn đang chờ cất
local function storeFruit()
    local pending = 0

    for _, v in ipairs(getHeldFruits()) do
        if not storeFailed[v] then
            pending = pending + 1
            if not storingTools[v] then
                task.spawn(storeTool, v)
            end
        end
    end

    return pending
end

-- Theo dõi: hễ có trái mới vào Backpack/Character là cất ngay
local function onChildAdded(child)
    task.spawn(function()
        task.wait(0.1) -- chờ tool load xong con bên trong
        if child.Parent and isFruitTool(child) then
            storeTool(child)
        end
    end)
end

local function hookContainer(container)
    if not container then return end
    container.ChildAdded:Connect(onChildAdded)
    for _, v in ipairs(container:GetChildren()) do
        onChildAdded(v)
    end
end

local function hookWatchers()
    hookContainer(LocalPlayer:FindFirstChildOfClass("Backpack") or LocalPlayer:WaitForChild("Backpack", 10))
    hookContainer(LocalPlayer.Character)

    -- Respawn: Character và Backpack được tạo mới
    LocalPlayer.CharacterAdded:Connect(function(char)
        hookContainer(char)
        task.wait(1)
        hookContainer(LocalPlayer:FindFirstChildOfClass("Backpack"))
    end)
end

-- ================= SERVER HOP (thuần Lua) =================
local function fetchJob()
    local cursor = ""
    local pages = 0

    repeat
        local url = "https://games.roblox.com/v1/games/"
            .. tostring(game.PlaceId)
            .. "/servers/Public?sortOrder=Asc&limit=100"
        if cursor ~= "" then
            url = url .. "&cursor=" .. cursor
        end

        local ok, res = pcall(request, {Url = url, Method = "GET"})
        if not ok or not res then
            return nil, "error"
        end
        if res.StatusCode == 429 then
            return nil, "ratelimit"
        end
        if res.StatusCode ~= 200 then
            return nil, "error"
        end

        local okJson, data = pcall(function()
            return HttpService:JSONDecode(res.Body)
        end)
        if not okJson or not data or not data.data then
            return nil, "error"
        end

        local candidates = {}
        for _, s in ipairs(data.data) do
            if s.playing >= MIN_TARGET
                and s.playing <= MAX_TARGET
                and s.id ~= game.JobId
                and not visited[s.id] then
                table.insert(candidates, s.id)
            end
        end

        -- Chọn ngẫu nhiên để nhiều acc không nhảy trùng cùng 1 server
        if #candidates > 0 then
            return candidates[math.random(1, #candidates)]
        end

        cursor = data.nextPageCursor
        pages = pages + 1
        task.wait(0.5)
    until not cursor or pages >= MAX_PAGES

    return nil, "none"
end

local function doHop()
    if isTeleporting then return end
    isTeleporting = true

    Status.Text = "📡 Đang tìm server 1-2 người..."
    Status.TextColor3 = Color3.fromRGB(0, 255, 255)

    task.wait(math.random(1, 3))

    local targetJobId, reason = fetchJob()

    if targetJobId then
        visited[targetJobId] = os.time()
        saveVisited()

        Status.Text = "🚀 Đang nhảy server..."
        task.wait(0.5)

        local ok = pcall(function()
            ReplicatedStorage.__ServerBrowser:InvokeServer("teleport", targetJobId)
        end)
        if not ok then
            pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, targetJobId, LocalPlayer)
            end)
        end

        task.delay(15, function()
            isTeleporting = false
        end)
    else
        if reason == "ratelimit" then
            Status.Text = "⚠️ Rate limit - nghỉ 25s..."
            Status.TextColor3 = Color3.fromRGB(255, 100, 0)
            task.wait(25)
        else
            Status.Text = "⏳ Chưa thấy server phù hợp..."
            Status.TextColor3 = Color3.fromRGB(255, 100, 0)
            task.wait(5)
        end
        isTeleporting = false
    end
end

-- ================= FIND FRUIT =================
-- Trái nào nhặt thất bại sẽ bị bỏ qua (weak table)
local failedFruits = setmetatable({}, {__mode = "k"})

-- Tên các trái bị bỏ qua ở lần quét gần nhất (để hiện lên GUI)
local lastSkipped = ""

-- Liệt kê mọi trái đang nằm dưới đất
local function listWorldFruits()
    local list = {}

    local worldOrigin = workspace:FindFirstChild("_WorldOrigin")
    local fruitSpawns = worldOrigin and worldOrigin:FindFirstChild("FruitSpawns")

    if fruitSpawns then
        for _, v in ipairs(fruitSpawns:GetChildren()) do
            if string.find(v.Name:lower(), "fruit") and not failedFruits[v] then
                if v:FindFirstChild("Fruit") then
                    table.insert(list, v)
                else
                    warn("Fruit sai structure -> bỏ qua")
                end
            end
        end
    end

    for _, v in ipairs(workspace:GetChildren()) do
        if v:IsA("Model") or v:IsA("Tool") then
            if string.find(v.Name:lower(), "fruit")
                and v.Name ~= "FruitSpawns"
                and not failedFruits[v] then
                if v:FindFirstChild("Fruit") or v:FindFirstChild("Handle") then
                    table.insert(list, v)
                else
                    warn("Fruit sai structure -> bỏ qua")
                end
            end
        end
    end

    return list
end

-- Trả về: instance trái được phép nhặt + tên trái, hoặc nil nếu không có
local function findFruit()
    local skipped, skippedSeen = {}, {}

    local function skip(name)
        if not skippedSeen[name] then
            skippedSeen[name] = true
            table.insert(skipped, name)
        end
    end

    local foundFruit, foundName

    for _, v in ipairs(listWorldFruits()) do
        local name = identifyFruit(v)

        if name then
            if ALLOWED_SET[name] then
                if not foundFruit then
                    foundFruit, foundName = v, name
                end
            else
                skip(name)
            end
        else
            if PICK_UNKNOWN then
                if not foundFruit then
                    foundFruit, foundName = v, "Fruit"
                end
            else
                skip("Fruit (không rõ)")
            end
        end
    end

    lastSkipped = table.concat(skipped, ", ")

    return foundFruit, foundName
end

-- Lấy BasePart đại diện của trái để bay tới
local function getFruitPart(fruit)
    if not fruit or not fruit.Parent then return nil end
    if fruit:IsA("BasePart") then return fruit end

    local handle = fruit:FindFirstChild("Handle")
    if handle and handle:IsA("BasePart") then return handle end

    local inner = fruit:FindFirstChild("Fruit")
    if inner then
        if inner:IsA("BasePart") then return inner end
        for _, d in ipairs(inner:GetDescendants()) do
            if d:IsA("BasePart") then return d end
        end
    end

    for _, d in ipairs(fruit:GetDescendants()) do
        if d:IsA("BasePart") then return d end
    end

    return nil
end

-- ================= COLLECT FRUIT =================
local function collectFruit(fruit)
    if isCollecting then return false end
    isCollecting = true

    local success = false
    local noclipConn, bv

    local ok, err = pcall(function()
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        -- Noclip + giữ nhân vật không rơi trong lúc bay
        noclipConn = RunService.Stepped:Connect(function()
            local c = LocalPlayer.Character
            if c then
                for _, p in ipairs(c:GetDescendants()) do
                    if p:IsA("BasePart") then
                        p.CanCollide = false
                    end
                end
            end
        end)

        bv = Instance.new("BodyVelocity")
        bv.Velocity = Vector3.zero
        bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
        bv.Parent = hrp

        local startTime = tick()
        local heldBefore = #getHeldFruits()
        local farFails = 0

        while fruit and fruit.Parent and not isTeleporting
            and (tick() - startTime) < COLLECT_TIMEOUT do

            -- Đã có trái mới trên người = nhặt xong, dừng ngay (không đụng thêm)
            if #getHeldFruits() > heldBefore then
                success = true
                break
            end

            local part = getFruitPart(fruit)
            if not part then break end

            char = LocalPlayer.Character
            hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then break end

            local targetCF = part.CFrame
            local dist = (hrp.Position - targetCF.Position).Magnitude

            if dist > 6 then
                local tween = TweenService:Create(
                    hrp,
                    TweenInfo.new(math.max(dist / FLY_SPEED, 0.1), Enum.EasingStyle.Linear),
                    {CFrame = targetCF}
                )
                tween:Play()
                tween.Completed:Wait()
            end

            -- Chạm vào trái để nhặt
            hrp.CFrame = targetCF
            if firetouchinterest then
                pcall(function()
                    firetouchinterest(hrp, part, 0)
                    task.wait()
                    firetouchinterest(hrp, part, 1)
                end)
            end

            task.wait(0.3)

            -- Chống kẹt: bị kéo ngược về xa trái nhiều lần thì bỏ trái này
            local nowPart = getFruitPart(fruit)
            local nowHrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            if nowPart and nowHrp then
                if (nowHrp.Position - nowPart.Position).Magnitude > 30 then
                    farFails = farFails + 1
                else
                    farFails = 0
                end
                if farFails >= 3 then
                    break
                end
            end
        end

        -- Nhặt xong = có trái mới trên người, hoặc trái biến mất khỏi workspace
        if #getHeldFruits() > heldBefore or not (fruit and fruit.Parent) then
            success = true
        end
    end)

    if not ok then
        warn("Lỗi nhặt trái: " .. tostring(err))
    end

    if noclipConn then noclipConn:Disconnect() end
    if bv then bv:Destroy() end

    if not success then
        failedFruits[fruit] = true
    end

    isCollecting = false
    return success
end

-- ================= FACTORY CHECK =================
local function checkFactory()
    for _, v in pairs(workspace:GetDescendants()) do
        if (v.Name == "Core" or v.Name == "Enemy") and v:IsA("Model") then
            local hum = v:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                return true
            end
        end
    end

    return false
end

-- ================= MAIN LOGIC =================
local function mainLogic()
    if isTeleporting or isCollecting then return end

    if checkFactory() then
        FactoryStatus.Text = "🏭 CÓ FACTORY!"
        FactoryStatus.TextColor3 = Color3.fromRGB(255, 0, 255)
        Status.Text = "⚔️ Đang chờ farm Factory"
        return
    end

    FactoryStatus.Text = "🏭 Factory: Đóng"
    FactoryStatus.TextColor3 = Color3.fromRGB(150, 150, 150)

    local fruit, fruitName = findFruit()

    if fruit then
        -- Chờ cất xong trái đang cầm (nếu có) trước khi nhặt trái mới
        local w = 0
        while w < 3 and storeFruit() > 0 do
            Status.Text = "📦 Đang cất trái trước khi nhặt tiếp..."
            task.wait(0.5)
            w = w + 0.5
        end

        if hasStuckFruit() then
            -- Game không cho cầm thêm trái (báo đỏ "You cannot..."), nên không nhặt nữa
            Status.Text = "🎒 Trái đang cầm cất không được -> bỏ qua nhặt"
            Status.TextColor3 = Color3.fromRGB(255, 150, 0)
        else
            FruitStatus.Text = "✅ THẤY TRÁI: " .. tostring(fruitName)
            FruitStatus.TextColor3 = Color3.fromRGB(0, 255, 100)
            Status.Text = "🍎 Đang bay tới nhặt trái..."
            Status.TextColor3 = Color3.fromRGB(255, 255, 255)

            local got = collectFruit(fruit)

            if got then
                Status.Text = "📦 Nhặt xong, đang cất vào túi..."
                storeFruit()
            else
                Status.Text = "⚠️ Nhặt thất bại, bỏ qua trái này"
            end

            task.wait(0.3)
            return
        end
    else
        if lastSkipped ~= "" then
            FruitStatus.Text = "❌ Bỏ qua: " .. string.sub(lastSkipped, 1, 30)
        else
            FruitStatus.Text = "❌ Không có trái (đã cất " .. totalStored .. ")"
        end
        FruitStatus.TextColor3 = Color3.fromRGB(255, 100, 100)
        Status.Text = "📦 Đang cất nốt trái trên người..."
    end

    -- Không nhặt được nữa: chờ cất xong (tối đa HOP_WAIT_STORE giây) rồi hop.
    -- Trái cất lỗi sẽ KHÔNG chặn việc hop.
    local waited = 0
    while waited < HOP_WAIT_STORE do
        if storeFruit() == 0 then break end
        task.wait(0.5)
        waited = waited + 0.5
    end

    local myName = LocalPlayer.Name:lower()

    for _, p in pairs(Players:GetPlayers()) do
        if p ~= LocalPlayer then
            for _, teamMember in pairs(MyTeam) do
                if p.Name:lower() == teamMember:lower() then
                    if myName > p.Name:lower() then
                        Status.Text = "👥 Trùng Acc: " .. p.Name
                        doHop()
                        return
                    end
                end
            end
        end
    end

    doHop()
end

-- ================= CHỜ MAP LOAD =================
-- Khi mới vào server, map/trái chưa load kịp nên không được hop ngay
local function waitForWorld()
    Status.Text = "⏳ Đang chờ load map..."
    Status.TextColor3 = Color3.fromRGB(255, 200, 0)

    -- Chờ nhân vật
    local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    char:WaitForChild("HumanoidRootPart", 15)

    -- Chờ map
    pcall(function()
        workspace:WaitForChild("_WorldOrigin", 10)
    end)

    -- Quét trong SETTLE_TIME giây, thấy trái (được phép nhặt) hoặc factory thì dừng chờ
    local t0 = tick()
    while tick() - t0 < SETTLE_TIME do
        FruitStatus.Text = "🍎 Đang quét trái... " .. math.ceil(SETTLE_TIME - (tick() - t0)) .. "s"
        FruitStatus.TextColor3 = Color3.fromRGB(255, 255, 255)
        if findFruit() or checkFactory() then break end
        task.wait(1)
    end
end

-- ================= START =================
task.spawn(function()
    if not game:IsLoaded() then game.Loaded:Wait() end

    local startTime = tick()

    task.spawn(function()
        while task.wait(1) do
            TimerLabel.Text = "⏱️ Uptime: " .. math.floor(tick() - startTime) .. "s"
        end
    end)

    task.wait(1)

    -- Chọn team trước khi chạy logic chính
    pcall(chooseTeam)

    -- Bật theo dõi: có trái vào túi là cất ngay
    pcall(hookWatchers)

    -- Chờ map load + quét trái trước khi quyết định hop
    pcall(waitForWorld)

    while true do
        local success, err = pcall(mainLogic)

        if not success then
            warn("Lỗi logic: " .. tostring(err))
        end

        task.wait(1)
    end
end)
