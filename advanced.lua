--[[
    Advanced Hub - 横向UI | 自瞄(预测+尸体过滤) | 高亮+射线透视
    所有参数可按钮调节或手动输入
]]

if _G.HubLoaded then
    if _G.HubUI then _G.HubUI:Destroy() end
end
_G.HubLoaded = true

-- 服务
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Camera = Workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- ========== 配置变量 ==========
local AimEnabled = false
local AimSmoothness = 3        -- 平滑度 1~10，值越大越平滑
local AimPrediction = 0.1      -- 预测时间（秒）
local AimFOVRadius = 130
local AimFOVColor = Color3.fromRGB(255, 255, 255)
local AimTeamCheck = false
local AimWallCheck = true
local AimPart = "Head"

local ESPEnabled = false
local ESPTeamCheck = false
local ESPMaxDistance = 1000
local ESPHighlightColor = Color3.fromRGB(255, 255, 255)
local ESPOutlineColor = Color3.fromRGB(255, 255, 255)
local ESPTracersEnabled = false
local ESPTracerColor = Color3.fromRGB(255, 255, 255)

-- 自瞄内部状态
local lockedTarget = nil
local lastTargetPos = nil
local targetVelocity = Vector3.zero

-- 透视资源
local highlightFolder = Instance.new("Folder")
highlightFolder.Name = "ESPHighlights"
highlightFolder.Parent = game:GetService("CoreGui")
local tracerLines = {}

-- ========== 高亮管理 ==========
local function clearHighlights()
    for _, v in ipairs(highlightFolder:GetChildren()) do v:Destroy() end
end

local function createHighlight(player)
    if highlightFolder:FindFirstChild(player.Name) then return end
    local hl = Instance.new("Highlight")
    hl.Name = player.Name
    hl.FillColor = ESPHighlightColor
    hl.OutlineColor = ESPOutlineColor
    hl.FillTransparency = 0.5
    hl.OutlineTransparency = 0
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.Adornee = player.Character
    hl.Parent = highlightFolder
end

local function updateHighlights()
    clearHighlights()
    if not ESPEnabled then return end
    local camPos = Camera.CFrame.Position
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if ESPTeamCheck and player.Team == LocalPlayer.Team then continue end
        local char = player.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        if (root.Position - camPos).Magnitude > ESPMaxDistance then continue end
        createHighlight(player)
    end
end

-- ========== 射线管理 ==========
local function updateTracers()
    for player, line in pairs(tracerLines) do
        if not player.Parent or not player.Character then line:Remove(); tracerLines[player] = nil end
    end
    if not ESPTracersEnabled or not ESPEnabled then
        for _, line in pairs(tracerLines) do line.Visible = false end
        return
    end
    local screenBottom = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
    local camPos = Camera.CFrame.Position
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if ESPTeamCheck and player.Team == LocalPlayer.Team then continue end
        local char = player.Character
        if not char then continue end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        if (root.Position - camPos).Magnitude > ESPMaxDistance then continue end
        local rootPos, onScreen = Camera:WorldToViewportPoint(root.Position)
        if not onScreen then continue end
        if not tracerLines[player] then
            local line = Drawing.new("Line")
            line.Thickness = 1
            line.Color = ESPTracerColor
            line.Transparency = 0.5
            tracerLines[player] = line
        end
        local line = tracerLines[player]
        line.Visible = true
        line.From = screenBottom
        line.To = Vector2.new(rootPos.X, rootPos.Y)
        line.Color = ESPTracerColor
    end
end

Players.PlayerAdded:Connect(function(player)
    player.CharacterAdded:Connect(function()
        if ESPEnabled then updateHighlights() end
    end)
end)

task.spawn(function()
    while true do
        if ESPEnabled then updateHighlights() else clearHighlights() end
        task.wait(0.3)
    end
end)
RunService.RenderStepped:Connect(updateTracers)

-- ========== FOV 圆圈（居中空心） ==========
local fovCircle = Drawing.new("Circle")
fovCircle.Filled = false
fovCircle.Thickness = 2.5
fovCircle.Transparency = 0.7
fovCircle.ZIndex = 999
fovCircle.Visible = false

-- ========== 自瞄目标验证（含尸体过滤） ==========
local function isValidAimTarget(player)
    if not player or player == LocalPlayer then return false end
    if AimTeamCheck and player.Team == LocalPlayer.Team then return false end
    local char = player.Character
    if not char then return false end
    local humanoid = char:FindFirstChild("Humanoid")
    -- 必须存在Humanoid且生命值大于0（不锁尸体）
    if not humanoid or humanoid.Health <= 0 then return false end
    local part = char:FindFirstChild(AimPart)
    if not part then return false end
    local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
    if not onScreen then return false end
    local center = Camera.ViewportSize / 2
    if (Vector2.new(pos.X, pos.Y) - center).Magnitude > AimFOVRadius then return false end
    if AimWallCheck then
        local camPos = Camera.CFrame.Position
        local rayParams = RaycastParams.new()
        rayParams.FilterDescendantsInstances = {LocalPlayer.Character, char}
        rayParams.FilterType = Enum.RaycastFilterType.Blacklist
        local ray = Workspace:Raycast(camPos, (part.Position - camPos), rayParams)
        if ray and ray.Instance then return false end
    end
    return true
end

local function findClosestTarget()
    local best = nil
    local shortest = AimFOVRadius + 999
    local center = Camera.ViewportSize / 2
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        if AimTeamCheck and player.Team == LocalPlayer.Team then continue end
        local char = player.Character
        if not char then continue end
        local humanoid = char:FindFirstChild("Humanoid")
        if not humanoid or humanoid.Health <= 0 then continue end
        local part = char:FindFirstChild(AimPart)
        if not part then continue end
        local pos, onScreen = Camera:WorldToViewportPoint(part.Position)
        if not onScreen then continue end
        local dist = (Vector2.new(pos.X, pos.Y) - center).Magnitude
        if dist > AimFOVRadius then continue end
        if AimWallCheck then
            local camPos = Camera.CFrame.Position
            local rayParams = RaycastParams.new()
            rayParams.FilterDescendantsInstances = {LocalPlayer.Character, char}
            rayParams.FilterType = Enum.RaycastFilterType.Blacklist
            local ray = Workspace:Raycast(camPos, (part.Position - camPos), rayParams)
            if ray and ray.Instance then continue end
        end
        if dist < shortest then
            shortest = dist
            best = player
        end
    end
    return best
end

-- ========== 自瞄执行循环 ==========
RunService:BindToRenderStep("MainAim", Enum.RenderPriority.Camera.Value, function()
    if not AimEnabled then
        fovCircle.Visible = false
        lockedTarget = nil
        return
    end

    -- 绘制FOV圆圈
    fovCircle.Position = Camera.ViewportSize / 2
    fovCircle.Radius = AimFOVRadius
    fovCircle.Color = AimFOVColor
    fovCircle.Visible = true

    -- 自动换目标（最靠近准心的敌人）
    local newTarget = findClosestTarget()
    if newTarget ~= lockedTarget then
        lockedTarget = newTarget
        targetVelocity = Vector3.zero
        lastTargetPos = nil
    end

    -- 检查锁定目标是否仍然有效
    if lockedTarget and not isValidAimTarget(lockedTarget) then
        lockedTarget = nil
        targetVelocity = Vector3.zero
        lastTargetPos = nil
        return
    end

    if not lockedTarget then return end

    local char = lockedTarget.Character
    if not char then return end
    local part = char:FindFirstChild(AimPart)
    if not part then return end

    local currentPos = part.Position

    -- 计算速度（用于预测）
    if lastTargetPos then
        local deltaTime = 1 / 60
        targetVelocity = (currentPos - lastTargetPos) / deltaTime
    end
    lastTargetPos = currentPos

    -- 预测位置
    local predictedPos = currentPos + targetVelocity * AimPrediction

    -- 平滑锁定
    local camPos = Camera.CFrame.Position
    local direction = (predictedPos - camPos).Unit
    local targetCF = CFrame.new(camPos, camPos + direction)

    -- 平滑度转alpha：平滑度越高，alpha越小（更平滑），1~10映射到0.1~0.8
    local alpha = math.clamp(1 / AimSmoothness, 0.05, 0.8)
    Camera.CFrame = Camera.CFrame:Lerp(targetCF, alpha)
end)

-- ========== GUI 构建 ==========
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "HubUI"
ScreenGui.Parent = game:GetService("CoreGui")
if syn and syn.protect_gui then syn.protect_gui(ScreenGui) elseif gethui then ScreenGui.Parent = gethui() end
_G.HubUI = ScreenGui

-- 主框架
local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 500, 0, 340)
MainFrame.Position = UDim2.new(0.5, -250, 0.5, -170)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
Instance.new("UICorner", MainFrame).CornerRadius = UDim.new(0, 8)

-- 标题栏
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 30)
TitleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame
Instance.new("UICorner", TitleBar).CornerRadius = UDim.new(0, 8)

local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(0.7, 0, 1, 0)
TitleText.Position = UDim2.new(0, 15, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "Advanced Hub"
TitleText.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleText.TextXAlignment = Enum.TextXAlignment.Left
TitleText.Font = Enum.Font.GothamBold
TitleText.TextSize = 14
TitleText.Parent = TitleBar

-- 最小化按钮
local MinimizeButton = Instance.new("TextButton")
MinimizeButton.Size = UDim2.new(0, 28, 0, 22)
MinimizeButton.Position = UDim2.new(1, -65, 0, 4)
MinimizeButton.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
MinimizeButton.Text = "—"
MinimizeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
MinimizeButton.Font = Enum.Font.GothamBold
MinimizeButton.TextSize = 16
MinimizeButton.BorderSizePixel = 0
MinimizeButton.Parent = TitleBar
Instance.new("UICorner", MinimizeButton).CornerRadius = UDim.new(0, 4)

-- 关闭按钮
local CloseButton = Instance.new("TextButton")
CloseButton.Size = UDim2.new(0, 28, 0, 22)
CloseButton.Position = UDim2.new(1, -32, 0, 4)
CloseButton.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
CloseButton.Text = "✕"
CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseButton.Font = Enum.Font.GothamBold
CloseButton.TextSize = 14
CloseButton.BorderSizePixel = 0
CloseButton.Parent = TitleBar
Instance.new("UICorner", CloseButton).CornerRadius = UDim.new(0, 4)

-- 内容区
local ContentFrame = Instance.new("Frame")
ContentFrame.Size = UDim2.new(1, 0, 1, -30)
ContentFrame.Position = UDim2.new(0, 0, 0, 30)
ContentFrame.BackgroundTransparency = 1
ContentFrame.Parent = MainFrame

-- 左侧类别
local CategoryFrame = Instance.new("Frame")
CategoryFrame.Size = UDim2.new(0, 110, 1, -10)
CategoryFrame.Position = UDim2.new(0, 5, 0, 5)
CategoryFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
CategoryFrame.BorderSizePixel = 0
CategoryFrame.Parent = ContentFrame
Instance.new("UICorner", CategoryFrame).CornerRadius = UDim.new(0, 6)

local CategoryScrolling = Instance.new("ScrollingFrame")
CategoryScrolling.Size = UDim2.new(1, -4, 1, -4)
CategoryScrolling.Position = UDim2.new(0, 2, 0, 2)
CategoryScrolling.BackgroundTransparency = 1
CategoryScrolling.ScrollBarThickness = 3
CategoryScrolling.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
CategoryScrolling.CanvasSize = UDim2.new(0, 0, 0, 200)
CategoryScrolling.Parent = CategoryFrame
Instance.new("UIListLayout", CategoryScrolling).Padding = UDim.new(0, 3)
CategoryScrolling.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
CategoryScrolling.UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

-- 右侧功能
local FunctionFrame = Instance.new("Frame")
FunctionFrame.Size = UDim2.new(1, -125, 1, -10)
FunctionFrame.Position = UDim2.new(0, 120, 0, 5)
FunctionFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
FunctionFrame.BorderSizePixel = 0
FunctionFrame.Parent = ContentFrame
Instance.new("UICorner", FunctionFrame).CornerRadius = UDim.new(0, 6)

local FunctionScrolling = Instance.new("ScrollingFrame")
FunctionScrolling.Size = UDim2.new(1, -4, 1, -4)
FunctionScrolling.Position = UDim2.new(0, 2, 0, 2)
FunctionScrolling.BackgroundTransparency = 1
FunctionScrolling.ScrollBarThickness = 3
FunctionScrolling.ScrollBarImageColor3 = Color3.fromRGB(60, 60, 60)
FunctionScrolling.CanvasSize = UDim2.new(0, 0, 0, 500)
FunctionScrolling.Parent = FunctionFrame
Instance.new("UIListLayout", FunctionScrolling).Padding = UDim.new(0, 5)
FunctionScrolling.UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
FunctionScrolling.UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder

local FunctionPages = {}
local CategoryButtons = {}

-- ===== 组件 =====
local function CreateCategoryButton(name, pageKey)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -10, 0, 28)
    btn.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(180, 180, 180)
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 12
    btn.BorderSizePixel = 0
    btn.Parent = CategoryScrolling
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    btn.MouseButton1Click:Connect(function()
        for _, b in ipairs(CategoryButtons) do
            b.BackgroundColor3 = Color3.fromRGB(35, 35, 35)
            b.TextColor3 = Color3.fromRGB(180, 180, 180)
        end
        btn.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
        btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        for k, page in pairs(FunctionPages) do
            page.Visible = (k == pageKey)
        end
    end)
    table.insert(CategoryButtons, btn)
    return btn
end

local function CreateFunctionPage(pageKey)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, -10, 0, 400)
    frame.BackgroundTransparency = 1
    frame.Visible = false
    frame.Parent = FunctionScrolling
    local list = Instance.new("UIListLayout")
    list.Padding = UDim.new(0, 4)
    list.HorizontalAlignment = Enum.HorizontalAlignment.Center
    list.SortOrder = Enum.SortOrder.LayoutOrder
    list.Parent = frame
    FunctionPages[pageKey] = frame
    return frame
end

-- 开关
local function CreateToggle(parent, text, default, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 32)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.65, 0, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local toggle = Instance.new("TextButton")
    toggle.Size = UDim2.new(0, 36, 0, 18)
    toggle.Position = UDim2.new(1, -44, 0, 7)
    toggle.BackgroundColor3 = default and Color3.fromRGB(0, 170, 80) or Color3.fromRGB(80, 80, 80)
    toggle.Text = ""
    toggle.BorderSizePixel = 0
    toggle.Parent = frame
    Instance.new("UICorner", toggle).CornerRadius = UDim.new(1, 0)

    local enabled = default
    toggle.MouseButton1Click:Connect(function()
        enabled = not enabled
        toggle.BackgroundColor3 = enabled and Color3.fromRGB(0, 170, 80) or Color3.fromRGB(80, 80, 80)
        callback(enabled)
    end)
    return frame
end

-- 步进器（- / + 按钮 + 点击数值输入）
local function CreateStepper(parent, text, minVal, maxVal, default, step, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 35)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.45, 0, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local current = default
    local valueLabel = Instance.new("TextButton")
    valueLabel.Size = UDim2.new(0, 40, 0, 20)
    valueLabel.Position = UDim2.new(0.5, 5, 0, 7)
    valueLabel.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    valueLabel.Text = tostring(current)
    valueLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    valueLabel.Font = Enum.Font.GothamBold
    valueLabel.TextSize = 12
    valueLabel.BorderSizePixel = 0
    valueLabel.Parent = frame
    Instance.new("UICorner", valueLabel).CornerRadius = UDim.new(0, 4)

    local minusBtn = Instance.new("TextButton")
    minusBtn.Size = UDim2.new(0, 22, 0, 22)
    minusBtn.Position = UDim2.new(0.5, -28, 0, 6)
    minusBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    minusBtn.Text = "-"
    minusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    minusBtn.Font = Enum.Font.GothamBold
    minusBtn.TextSize = 16
    minusBtn.BorderSizePixel = 0
    minusBtn.Parent = frame
    Instance.new("UICorner", minusBtn).CornerRadius = UDim.new(0, 4)

    local plusBtn = Instance.new("TextButton")
    plusBtn.Size = UDim2.new(0, 22, 0, 22)
    plusBtn.Position = UDim2.new(0.5, 45, 0, 6)
    plusBtn.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    plusBtn.Text = "+"
    plusBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    plusBtn.Font = Enum.Font.GothamBold
    plusBtn.TextSize = 16
    plusBtn.BorderSizePixel = 0
    plusBtn.Parent = frame
    Instance.new("UICorner", plusBtn).CornerRadius = UDim.new(0, 4)

    local function update(val)
        val = math.clamp(tonumber(val) or current, minVal, maxVal)
        current = val
        valueLabel.Text = tostring(current)
        callback(current)
    end

    minusBtn.MouseButton1Click:Connect(function() update(current - step) end)
    plusBtn.MouseButton1Click:Connect(function() update(current + step) end)

    valueLabel.MouseButton1Click:Connect(function()
        local input = Instance.new("TextBox")
        input.Size = UDim2.new(0, 60, 0, 22)
        input.Position = UDim2.new(0.5, -30, 0, 6)
        input.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
        input.TextColor3 = Color3.fromRGB(255, 255, 255)
        input.Font = Enum.Font.GothamBold
        input.TextSize = 12
        input.Text = tostring(current)
        input.Parent = frame
        input:CaptureFocus()
        input.FocusLost:Connect(function(enterPressed)
            update(tonumber(input.Text))
            input:Destroy()
        end)
    end)
    return frame
end

-- 颜色选择器（循环切换）
local function CreateColorPicker(parent, text, defaultColor, callback)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 35)
    frame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    frame.BorderSizePixel = 0
    frame.Parent = parent
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 4)

    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(0.5, 0, 1, 0)
    label.Position = UDim2.new(0, 8, 0, 0)
    label.BackgroundTransparency = 1
    label.Text = text
    label.TextColor3 = Color3.fromRGB(220, 220, 220)
    label.Font = Enum.Font.GothamSemibold
    label.TextSize = 12
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame

    local colorBtn = Instance.new("TextButton")
    colorBtn.Size = UDim2.new(0, 30, 0, 20)
    colorBtn.Position = UDim2.new(1, -38, 0, 7)
    colorBtn.BackgroundColor3 = defaultColor
    colorBtn.Text = ""
    colorBtn.BorderSizePixel = 0
    colorBtn.Parent = frame
    Instance.new("UICorner", colorBtn).CornerRadius = UDim.new(0, 3)

    local colorList = {
        Color3.fromRGB(255,255,255), Color3.fromRGB(255,0,0), Color3.fromRGB(0,255,0),
        Color3.fromRGB(0,0,255), Color3.fromRGB(255,255,0), Color3.fromRGB(255,0,255),
        Color3.fromRGB(0,255,255), Color3.fromRGB(255,150,0)
    }
    local colorIndex = 1
    for i, col in ipairs(colorList) do
        if col.R == defaultColor.R and col.G == defaultColor.G and col.B == defaultColor.B then
            colorIndex = i
            break
        end
    end
    colorBtn.MouseButton1Click:Connect(function()
        colorIndex = colorIndex % #colorList + 1
        colorBtn.BackgroundColor3 = colorList[colorIndex]
        callback(colorList[colorIndex])
    end)
    return frame
end

-- 普通按钮
local function CreateButton(parent, text, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -10, 0, 28)
    btn.BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.BorderSizePixel = 0
    btn.Parent = parent
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
    btn.MouseButton1Click:Connect(callback)
    return btn
end

-- ========== 页面内容 ==========
-- 自瞄页
local AimPage = CreateFunctionPage("Aim")
CreateToggle(AimPage, "启用自瞄", false, function(v) AimEnabled = v end)
CreateToggle(AimPage, "队伍检查", false, function(v) AimTeamCheck = v end)
CreateToggle(AimPage, "掩体检查", true, function(v) AimWallCheck = v end)
CreateStepper(AimPage, "平滑度", 1, 10, AimSmoothness, 1, function(v) AimSmoothness = v end)
CreateStepper(AimPage, "预测时间", 0, 0.5, AimPrediction, 0.05, function(v) AimPrediction = v end)
CreateStepper(AimPage, "FOV半径", 50, 500, AimFOVRadius, 10, function(v) AimFOVRadius = v end)
CreateColorPicker(AimPage, "FOV颜色", AimFOVColor, function(c) AimFOVColor = c end)

-- 瞄准部位
local hitPartFrame = Instance.new("Frame")
hitPartFrame.Size = UDim2.new(1, 0, 0, 35)
hitPartFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
hitPartFrame.BorderSizePixel = 0
hitPartFrame.Parent = AimPage
Instance.new("UICorner", hitPartFrame).CornerRadius = UDim.new(0, 4)
local hitPartLabel = Instance.new("TextLabel")
hitPartLabel.Size = UDim2.new(0.4, 0, 1, 0)
hitPartLabel.Position = UDim2.new(0, 8, 0, 0)
hitPartLabel.BackgroundTransparency = 1
hitPartLabel.Text = "瞄准部位"
hitPartLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
hitPartLabel.Font = Enum.Font.GothamSemibold
hitPartLabel.TextSize = 12
hitPartLabel.TextXAlignment = Enum.TextXAlignment.Left
hitPartLabel.Parent = hitPartFrame
local hitParts = {"Head", "HumanoidRootPart", "UpperTorso", "LowerTorso"}
local hitPartIndex = 1
local hitPartBtn = Instance.new("TextButton")
hitPartBtn.Size = UDim2.new(0, 100, 0, 22)
hitPartBtn.Position = UDim2.new(1, -110, 0, 6)
hitPartBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
hitPartBtn.Text = hitParts[1]
hitPartBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
hitPartBtn.Font = Enum.Font.GothamSemibold
hitPartBtn.TextSize = 11
hitPartBtn.BorderSizePixel = 0
hitPartBtn.Parent = hitPartFrame
Instance.new("UICorner", hitPartBtn).CornerRadius = UDim.new(0, 4)
hitPartBtn.MouseButton1Click:Connect(function()
    hitPartIndex = hitPartIndex % #hitParts + 1
    hitPartBtn.Text = hitParts[hitPartIndex]
    AimPart = hitParts[hitPartIndex]
end)

-- 透视页
local ESPPage = CreateFunctionPage("ESP")
CreateToggle(ESPPage, "启用高亮", false, function(v) ESPEnabled = v end)
CreateToggle(ESPPage, "队伍检查", false, function(v) ESPTeamCheck = v end)
CreateStepper(ESPPage, "最大距离", 100, 5000, ESPMaxDistance, 50, function(v) ESPMaxDistance = v end)
CreateColorPicker(ESPPage, "填充颜色", ESPHighlightColor, function(c)
    ESPHighlightColor = c
    for _, hl in ipairs(highlightFolder:GetChildren()) do
        if hl:IsA("Highlight") then hl.FillColor = c end
    end
end)
CreateColorPicker(ESPPage, "轮廓颜色", ESPOutlineColor, function(c)
    ESPOutlineColor = c
    for _, hl in ipairs(highlightFolder:GetChildren()) do
        if hl:IsA("Highlight") then hl.OutlineColor = c end
    end
end)
CreateToggle(ESPPage, "射线", false, function(v)
    ESPTracersEnabled = v
    if not v then for _, line in pairs(tracerLines) do line.Visible = false end end
end)
CreateColorPicker(ESPPage, "射线颜色", ESPTracerColor, function(c) ESPTracerColor = c end)

-- 开枪页
local ShootPage = CreateFunctionPage("Shoot")
CreateButton(ShootPage, "使用抓包开枪数据", function()
    pcall(function()
        local args = {
            {
                {
                    Vector3.new(830.4642333984375, 101.48998260498047, 2263.4375),
                    Vector3.new(806.5999145507812, 98.83991241455078, 2271.4853515625),
                    workspace:WaitForChild("Doors"):WaitForChild("door_v3"):WaitForChild("block"):WaitForChild("hitbox")
                }
            }
        }
        game:GetService("ReplicatedStorage"):WaitForChild("GunRemotes"):WaitForChild("ShootEvent"):FireServer(unpack(args))
    end)
end)

-- 杂项页
local MiscPage = CreateFunctionPage("Misc")
CreateStepper(MiscPage, "视野(FOV)", 30, 120, 70, 1, function(v) Camera.FieldOfView = v end)
CreateStepper(MiscPage, "亮度", 0, 10, 1, 0.1, function(v) game:GetService("Lighting").Brightness = v end)

-- 类别按钮
CreateCategoryButton("🎯 自瞄", "Aim")
CreateCategoryButton("👁 透视", "ESP")
CreateCategoryButton("🔫 开枪", "Shoot")
CreateCategoryButton("🔧 杂项", "Misc")

-- 默认显示自瞄页
if FunctionPages["Aim"] and CategoryButtons[1] then
    FunctionPages["Aim"].Visible = true
    CategoryButtons[1].BackgroundColor3 = Color3.fromRGB(0, 120, 255)
    CategoryButtons[1].TextColor3 = Color3.fromRGB(255, 255, 255)
end

-- 最小化/关闭
local minimized = false
local originalSize = MainFrame.Size
MinimizeButton.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        ContentFrame.Visible = false
        MainFrame.Size = UDim2.new(0, 500, 0, 30)
        MinimizeButton.Text = "+"
    else
        ContentFrame.Visible = true
        MainFrame.Size = originalSize
        MinimizeButton.Text = "—"
    end
end)
CloseButton.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
    _G.HubLoaded = false
end)

-- 清理连接
LocalPlayer.CharacterAdded:Connect(function()
    lockedTarget = nil
    lastTargetPos = nil
    targetVelocity = Vector3.zero
end)
Players.PlayerRemoving:Connect(function(player)
    local hl = highlightFolder:FindFirstChild(player.Name)
    if hl then hl:Destroy() end
    if tracerLines[player] then
        tracerLines[player]:Remove()
        tracerLines[player] = nil
    end
end)