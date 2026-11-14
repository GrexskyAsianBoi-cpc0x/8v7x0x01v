local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local getinfo = getinfo or debug.getinfo
local Hooked = {}
local Detected, Kill
pcall(function() setthreadidentity(2) end)
for i, v in getgc(true) do
    if typeof(v) == "table" then
        local DetectFunc = rawget(v, "Detected")
        local KillFunc = rawget(v, "Kill")
        if typeof(DetectFunc) == "function" and not Detected then
            Detected = DetectFunc
            local Old; Old = hookfunction(Detected, function() return true end)
            table.insert(Hooked, Detected)
        end
        if rawget(v, "Variables") and rawget(v, "Process") and typeof(KillFunc) == "function" and not Kill then
            Kill = KillFunc
            local Old; Old = hookfunction(Kill, function() end)
            table.insert(Hooked, Kill)
        end
    end
end
pcall(function()
    local Old; Old = hookfunction(getrenv().debug.info, newcclosure(function(...)
        local LevelOrFunc, Info = ...
        if Detected and LevelOrFunc == Detected then
            return coroutine.yield(coroutine.running())
        end
        return Old(...)
    end))
end)
pcall(function() setthreadidentity(7) end)

local PLAYER_FILE = "CSTM_PlayerWhitelist.json"
local TEAM_FILE = "CSTM_TeamWhitelist.json"

local function loadWhitelist()
    local wl = {}
    if isfile and isfile(PLAYER_FILE) then
        local suc, data = pcall(function() return readfile(PLAYER_FILE) end)
        if suc and data and data ~= "" then
            local suc2, decoded = pcall(function() return HttpService:JSONDecode(data) end)
            if suc2 and type(decoded) == "table" then wl = decoded end
        end
    end
    getgenv().CSTM_Whitelist = wl

    local twl = {}
    if isfile and isfile(TEAM_FILE) then
        local suc, data = pcall(function() return readfile(TEAM_FILE) end)
        if suc and data and data ~= "" then
            local suc2, decoded = pcall(function() return HttpService:JSONDecode(data) end)
            if suc2 and type(decoded) == "table" then twl = decoded end
        end
    end
    getgenv().CSTM_TeamWhitelist = twl
end

local function saveWhitelist()
    if writefile then
        local suc1, data1 = pcall(function() return HttpService:JSONEncode(getgenv().CSTM_Whitelist) end)
        if suc1 then pcall(function() writefile(PLAYER_FILE, data1) end) end
        local suc2, data2 = pcall(function() return HttpService:JSONEncode(getgenv().CSTM_TeamWhitelist) end)
        if suc2 then pcall(function() writefile(TEAM_FILE, data2) end) end
    end
end

loadWhitelist()
if not getgenv().CSTM_TeamWhitelist then getgenv().CSTM_TeamWhitelist = {} end

local function getPlayerTeam(plr)
    local tags = {}
    if plr.Team then tags[#tags + 1] = plr.Team.Name:lower() end

    local ls = plr:FindFirstChild("leaderstats")
    if ls then
        for _, v in ipairs(ls:GetChildren()) do
            local n = v.Name:lower()
            if n:find("team") or n:find("clan") or n:find("dojo") or n:find("guild") or n:find("gang") or n:find("faction") then
                tags[#tags + 1] = tostring(v.Value):lower()
            end
        end
    end

    for _, attr in ipairs({"Team", "team", "Clan", "clan", "Dojo", "dojo", "Guild", "guild", "Gang", "gang", "Faction", "faction"}) do
        local ok, val = pcall(function() return plr:GetAttribute(attr) end)
        if ok and val then tags[#tags + 1] = tostring(val):lower() end
    end

    local char = plr.Character
    if char then
        for _, attr in ipairs({"Team", "team", "Clan", "clan", "Dojo", "dojo", "Guild", "guild"}) do
            local ok, val = pcall(function() return char:GetAttribute(attr) end)
            if ok and val then tags[#tags + 1] = tostring(val):lower() end
        end

        local head = char:FindFirstChild("Head")
        if head then
            for _, v in ipairs(head:GetDescendants()) do
                if v:IsA("BillboardGui") then
                    for _, t in ipairs(v:GetDescendants()) do
                        if t:IsA("TextLabel") and t.Text and t.Text ~= "" then
                            tags[#tags + 1] = t.Text:lower()
                        end
                    end
                end
            end
        end
    end
    return tags
end

local function playerInTeamWL(plr)
    local teamWL = getgenv().CSTM_TeamWhitelist
    if not teamWL or next(teamWL) == nil then return false end
    local tags = getPlayerTeam(plr)
    for _, tag in ipairs(tags) do
        for teamName, _ in pairs(teamWL) do
            if tag:find(teamName, 1, true) or teamName:find(tag, 1, true) then
                return true
            end
        end
    end
    return false
end

local function isPlayerWhitelisted(plr)
    if getgenv().CSTM_Whitelist[plr.Name:lower()] or getgenv().CSTM_Whitelist[plr.DisplayName:lower()] then
        return true
    end
    return playerInTeamWL(plr)
end

local HitboxEnabled = false
local HitboxSize = 2.45
local HitboxTransparency = 0.99999
local Multiplier = 2.5
local TARGET_SIZE = Vector3.new(HitboxSize * Multiplier, HitboxSize * Multiplier, HitboxSize * Multiplier)

local REFRESH_RATE = 0.05
local FACE_RATE = 1.0
local CLONE_CULL = 350

local originalSizes = setmetatable({}, {__mode = "k"})
local originalTransparencies = setmetatable({}, {__mode = "k"})
local originalCollides = setmetatable({}, {__mode = "k"})
local originalMassless = setmetatable({}, {__mode = "k"})
local targetPartsCache = setmetatable({}, {__mode = "k"})

local visualClones = setmetatable({}, {__mode = "k"}) 
local activeBoxes = setmetatable({}, {__mode = "k"}) 
local showBoxEnabled = true

local function recomputeTargetSize()
    TARGET_SIZE = Vector3.new(HitboxSize * Multiplier, HitboxSize * Multiplier, HitboxSize * Multiplier)
end

local oldIndex
oldIndex = hookmetamethod(game, "__index", newcclosure(function(self, key)
    if typeof(self) == "Instance" and self:IsA("BasePart") then
        if key == "Size" then
            local orig = originalSizes[self]
            if orig and not checkcaller() then return orig end
        elseif key == "Transparency" then
            local orig = originalTransparencies[self]
            if orig and not checkcaller() then return orig end
        elseif key == "CanCollide" then
            local orig = originalCollides[self]
            if orig ~= nil and not checkcaller() then return orig end
        elseif key == "Massless" then
            local orig = originalMassless[self]
            if orig ~= nil and not checkcaller() then return orig end
        end
    end
    return oldIndex(self, key)
end))

local function isTargetPart(partName)
    return partName == "Head" or partName == "Torso" or partName == "UpperTorso" or partName == "LowerTorso" or
           partName == "Right Arm" or partName == "Left Arm" or partName == "RightUpperArm" or
           partName == "LeftUpperArm" or partName == "RightLowerArm" or partName == "LeftLowerArm" or
           partName == "RightHand" or partName == "LeftHand"
end

local function saveOriginal(part)
    if not part then return end
    if not originalSizes[part] then originalSizes[part] = part.Size end
    if not originalTransparencies[part] then originalTransparencies[part] = part.Transparency end
    if originalCollides[part] == nil then originalCollides[part] = part.CanCollide end
    if originalMassless[part] == nil then originalMassless[part] = part.Massless end
end

local function stripFace(char)
    local head = char:FindFirstChild("Head")
    if head then
        for _, v in ipairs(head:GetChildren()) do
            if v:IsA("Decal") or v:IsA("Texture") then
                if v.Transparency ~= 1 then v.Transparency = 1 end
            end
        end
    end
end

local function createVisualClone(plr, char)
    local existing = visualClones[char]
    if existing and existing.model and existing.model.Parent then return end

    local clone = char:Clone()
    clone.Name = plr.Name .. "_FS_Visual"

    for _, v in ipairs(clone:GetDescendants()) do
        if v:IsA("Script") or v:IsA("LocalScript") or v:IsA("Humanoid") then
            v:Destroy()
        elseif v:IsA("Decal") or v:IsA("Texture") then
            if v.Parent and v.Parent.Name == "Head" then
                v:Destroy()
            end
        elseif v:IsA("BasePart") then
            v.CanCollide = false
            v.CanTouch = false
            v.CanQuery = false
            v.Massless = true
            v.Anchored = false
        end
    end

    local cloneHRP = clone:FindFirstChild("HumanoidRootPart")
    local origHRP = char:FindFirstChild("HumanoidRootPart")
    if cloneHRP and origHRP then
        cloneHRP.CFrame = origHRP.CFrame
        local weld = Instance.new("WeldConstraint")
        weld.Part0 = origHRP
        weld.Part1 = cloneHRP
        weld.Parent = cloneHRP
    end

    local motors = {}
    for _, mot in ipairs(char:GetDescendants()) do
        if mot:IsA("Motor6D") then
            local cm = clone:FindFirstChild(mot.Name, true)
            if cm and cm:IsA("Motor6D") then
                motors[#motors + 1] = {mot, cm}
            end
        end
    end

    clone.Parent = Camera
    visualClones[char] = {model = clone, motors = motors}
end

local function revertCharacter(char)
    if not char then return end
    local parts = targetPartsCache[char]
    if parts then
        for i = 1, #parts do
            local part = parts[i]
            if part and part.Parent then
                if originalSizes[part] then part.Size = originalSizes[part]; originalSizes[part] = nil end
                if originalTransparencies[part] then part.Transparency = originalTransparencies[part]; originalTransparencies[part] = nil end
                if originalCollides[part] ~= nil then part.CanCollide = originalCollides[part]; originalCollides[part] = nil end
                if originalMassless[part] ~= nil then part.Massless = originalMassless[part]; originalMassless[part] = nil end
                part.CustomPhysicalProperties = nil
            end
        end
        targetPartsCache[char] = nil
    end
    local box = activeBoxes[char]
    if box then box:Destroy(); activeBoxes[char] = nil end
    local vc = visualClones[char]
    if vc then
        if vc.model then vc.model:Destroy() end
        visualClones[char] = nil
    end
end

local function expandCharacter(char)
    if not char or not char.Parent then return end
    if not HitboxEnabled or targetPartsCache[char] then return end

    local list = {}
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and isTargetPart(part.Name) then
            saveOriginal(part)
            part.Size = TARGET_SIZE
            part.Transparency = HitboxTransparency
            part.CanCollide = false
            part.Massless = true
            part.CanTouch = true
            part.CustomPhysicalProperties = PhysicalProperties.new(0, 0, 0, 0, 0)
            list[#list + 1] = part
        end
    end
    targetPartsCache[char] = list

    stripFace(char)

    task.spawn(function()
        local plr = Players:GetPlayerFromCharacter(char)
        if plr then createVisualClone(plr, char) end
    end)

    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum and not char:GetAttribute("FS_Died_Conn") then
        char:SetAttribute("FS_Died_Conn", true)
        hum.Died:Connect(function() revertCharacter(char) end)
        hum.HealthChanged:Connect(function(h) if h <= 0 then revertCharacter(char) end end)
    end
end

local function applyPropsToChar(char, parts)
    for i = 1, #parts do
        local part = parts[i]
        if part and part.Parent then
            if part.Size ~= TARGET_SIZE then part.Size = TARGET_SIZE end
            if part.Transparency ~= HitboxTransparency then part.Transparency = HitboxTransparency end
            if part.CanCollide then part.CanCollide = false end
            if not part.Massless then part.Massless = true end
            if not part.CanTouch then part.CanTouch = true end
        end
    end
end

local function myPos()
    local c = LocalPlayer.Character
    local h = c and c:FindFirstChild("HumanoidRootPart")
    return h and h.Position or Vector3.zero
end

local refreshAcc, faceAcc = 0, 0

RunService.RenderStepped:Connect(function(dt)
    if not HitboxEnabled then return end

    for char, box in pairs(activeBoxes) do
        if char.Parent then
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hrp then box.CFrame = hrp.CFrame end
        end
    end

    refreshAcc = refreshAcc + dt
    if refreshAcc < REFRESH_RATE then return end
    refreshAcc = 0

    faceAcc = faceAcc + REFRESH_RATE
    local doFace = false
    if faceAcc >= FACE_RATE then faceAcc = 0; doFace = true end

    local origin = myPos()

    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") then
            if isPlayerWhitelisted(plr) then
                revertCharacter(plr.Character)
            else
                expandCharacter(plr.Character)
            end
        end
    end

    for char, parts in pairs(targetPartsCache) do
        if char and char.Parent then
            local hum = char:FindFirstChildOfClass("Humanoid")
            local hrp = char:FindFirstChild("HumanoidRootPart")
            if hum and hum.Health > 0 and hrp then
                if doFace then stripFace(char) end

                local vc = visualClones[char]
                if vc and vc.model then
                    local dist = (hrp.Position - origin).Magnitude
                    local want = dist < CLONE_CULL and Camera or nil
                    if vc.model.Parent ~= want then vc.model.Parent = want end
                    if want then
                        local ms = vc.motors
                        for i = 1, #ms do
                            local e = ms[i]
                            e[2].Transform = e[1].Transform
                        end
                    end
                end

                applyPropsToChar(char, parts)

                if showBoxEnabled then
                    local box = activeBoxes[char]
                    if not box or not box.Parent then
                        box = Instance.new("Part")
                        box.Name = "FS_BoxPreview"
                        box.Transparency = 1
                        box.Anchored = true
                        box.CanCollide = false
                        box.CanTouch = false
                        box.CanQuery = false
                        box.Size = TARGET_SIZE

                        local sel = Instance.new("SelectionBox")
                        sel.Adornee = box
                        sel.Color3 = Color3.fromRGB(255, 0, 0)
                        sel.LineThickness = 0.05
                        sel.SurfaceTransparency = 1
                        sel.Parent = box

                        box.Parent = Camera
                        activeBoxes[char] = box
                    end
                    if box.Size ~= TARGET_SIZE then box.Size = TARGET_SIZE end
                    box.CFrame = hrp.CFrame
                else
                    local box = activeBoxes[char]
                    if box then box:Destroy(); activeBoxes[char] = nil end
                end
            else
                revertCharacter(char)
            end
        else
            revertCharacter(char)
        end
    end
end)

local function applyInstantHitbox()
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer and plr.Character then
            if not isPlayerWhitelisted(plr) then
                expandCharacter(plr.Character)
                local parts = targetPartsCache[plr.Character]
                if parts then applyPropsToChar(plr.Character, parts) end
            end
        end
    end
end

local function revertAll()
    HitboxEnabled = false
    for char, _ in pairs(targetPartsCache) do
        revertCharacter(char)
    end
    targetPartsCache = setmetatable({}, {__mode = "k"})
end

local THEME = {
    bg=Color3.fromRGB(6,11,28), panel=Color3.fromRGB(10,19,46), row=Color3.fromRGB(14,27,62),
    accent=Color3.fromRGB(58,118,255), accent2=Color3.fromRGB(125,195,255),
    text=Color3.fromRGB(230,238,255), subtext=Color3.fromRGB(135,155,200), stroke=Color3.fromRGB(28,48,108),
    green=Color3.fromRGB(80,220,140), bad=Color3.fromRGB(240,90,110)
}
local T_FAST = TweenInfo.new(0.16, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

local gui = Instance.new("ScreenGui")
gui.Name = "Grexsky_" .. tostring(math.random(1000, 9999))
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
do
    local ok = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    if not ok or not gui.Parent then gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
end

local function new(c, p, ch)
    local i = Instance.new(c)
    for k, v in pairs(p or {}) do i[k] = v end
    for _, x in ipairs(ch or {}) do x.Parent = i end
    return i
end

local FINAL_SIZE = UDim2.fromOffset(180, 320)
local TOPBAR_H = 34
local minimized = false

local main = new("Frame", {
    Name="Main", Size=UDim2.fromOffset(0,0),
    AnchorPoint=Vector2.new(1, 0),
    Position=UDim2.new(1, -260, 0, 10),
    BackgroundColor3=THEME.bg, BorderSizePixel=0, ClipsDescendants=true, Parent=gui})
new("UICorner", {CornerRadius=UDim.new(0,8), Parent=main})
local bg = new("Frame", {Size=UDim2.fromScale(1,1), BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, ZIndex=0, Parent=main})
new("UICorner", {CornerRadius=UDim.new(0,8), Parent=bg})
new("UIGradient", {Color=ColorSequence.new{ColorSequenceKeypoint.new(0, Color3.fromRGB(3,7,20)), ColorSequenceKeypoint.new(1, Color3.fromRGB(13,30,76))}, Rotation=90, Parent=bg})
local outline = new("UIStroke", {Color=Color3.new(1,1,1), Thickness=1.2, ApplyStrokeMode=Enum.ApplyStrokeMode.Border, Parent=main})
local outlineG = new("UIGradient", {Color=ColorSequence.new{ColorSequenceKeypoint.new(0, THEME.accent), ColorSequenceKeypoint.new(0.3, Color3.new(1,1,1)), ColorSequenceKeypoint.new(0.6, Color3.fromRGB(8,16,44)), ColorSequenceKeypoint.new(1, THEME.accent)}, Parent=outline})
TweenService:Create(main, TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size=FINAL_SIZE}):Play()

local topbar = new("Frame", {Name="TopBar", Size=UDim2.new(1,-8,0,26), Position=UDim2.fromOffset(4,4), BackgroundColor3=THEME.panel, BackgroundTransparency=0.1, BorderSizePixel=0, ZIndex=2, Parent=main})
new("UICorner", {CornerRadius=UDim.new(0,5), Parent=topbar})
new("UIStroke", {Color=THEME.stroke, Thickness=1, Parent=topbar})

local title = new("TextLabel", {Text="0xC76B", Font=Enum.Font.GothamBlack, TextSize=11, TextColor3=Color3.new(1,1,1), TextXAlignment=Enum.TextXAlignment.Left, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(1,-60,1,0), ZIndex=3, Parent=topbar})
local titleG = new("UIGradient", {Color=ColorSequence.new{ColorSequenceKeypoint.new(0, THEME.accent2), ColorSequenceKeypoint.new(0.3, Color3.new(1,1,1)), ColorSequenceKeypoint.new(0.6, THEME.accent), ColorSequenceKeypoint.new(1, THEME.accent2)}, Parent=title})

local function topBtn(t, xOff)
    local b = new("TextButton", {Text=t, Font=Enum.Font.GothamBold, TextSize=14, TextColor3=THEME.subtext, BackgroundColor3=THEME.row, AutoButtonColor=false, Size=UDim2.fromOffset(24,24), Position=UDim2.new(1,xOff,0.5,-12), ZIndex=3, Parent=topbar})
    new("UICorner", {CornerRadius=UDim.new(0,4), Parent=b})
    return b
end
local minimizeBtn = topBtn("—", -56)
local closeBtn = topBtn("×", -28)

local hb = RunService.Heartbeat:Connect(function(dt)
    outlineG.Rotation = (outlineG.Rotation + dt * 140) % 360
    titleG.Rotation = (titleG.Rotation + dt * 90) % 360
end)

local dragging, dragStart, startPos = false, nil, nil
topbar.InputBegan:Connect(function(inp)
    if inp.UserInputType == Enum.UserInputType.MouseButton1 or inp.UserInputType == Enum.UserInputType.Touch then
        dragging = true; dragStart = inp.Position; startPos = main.Position
        inp.Changed:Connect(function() if inp.UserInputState == Enum.UserInputState.End then dragging = false end end)
    end
end)
UserInputService.InputChanged:Connect(function(inp)
    if dragging and (inp.UserInputType == Enum.UserInputType.MouseMovement or inp.UserInputType == Enum.UserInputType.Touch) then
        local d = inp.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
    end
end)

local content = new("Frame", {Size=UDim2.new(1,-12,1,-(TOPBAR_H+8)), Position=UDim2.fromOffset(6,TOPBAR_H), BackgroundTransparency=1, ZIndex=2, Parent=main}, {new("UIListLayout", {SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,4)})})

local toggleBtn, floatBtn

local function updateToggleState()
    if HitboxEnabled then
        if toggleBtn then
            toggleBtn.Text = "ENABLE [ON]"
            toggleBtn.BackgroundColor3 = THEME.accent
        end
        if floatBtn then
            floatBtn.Text = "HB ON"
            floatBtn.BackgroundColor3 = THEME.green
            floatBtn.TextColor3 = Color3.new(1,1,1)
        end
    else
        if toggleBtn then
            toggleBtn.Text = "ENABLE [OFF]"
            toggleBtn.BackgroundColor3 = THEME.row
        end
        if floatBtn then
            floatBtn.Text = "HB OFF"
            floatBtn.BackgroundColor3 = THEME.bad
            floatBtn.TextColor3 = Color3.new(1,1,1)
        end
    end
end

local function toggleAction()
    HitboxEnabled = not HitboxEnabled
    if HitboxEnabled then
        applyInstantHitbox() 
    else
        revertAll()
    end
    updateToggleState()
end

toggleBtn = new("TextButton", {Text="ENABLE [OFF]", Font=Enum.Font.GothamBold, TextSize=13, TextColor3=Color3.new(1,1,1), BackgroundColor3=THEME.row, AutoButtonColor=false, Size=UDim2.new(1,0,0,32), LayoutOrder=1, ZIndex=2, Parent=content})
new("UICorner", {CornerRadius=UDim.new(0,5), Parent=toggleBtn})
toggleBtn.MouseButton1Click:Connect(toggleAction)

local sizeRow = new("Frame", {Size=UDim2.new(1,0,0,24), BackgroundColor3=THEME.panel, BorderSizePixel=0, LayoutOrder=2, ZIndex=2, Parent=content})
new("UICorner", {CornerRadius=UDim.new(0,5), Parent=sizeRow})
new("UIStroke", {Color=THEME.stroke, Thickness=1, Parent=sizeRow})
new("TextLabel", {Text="SIZE", Font=Enum.Font.GothamBold, TextSize=10, TextColor3=THEME.subtext, TextXAlignment=Enum.TextXAlignment.Left, BackgroundTransparency=1, Position=UDim2.fromOffset(8,0), Size=UDim2.new(0,50,1,0), ZIndex=3, Parent=sizeRow})
local sizeInput = new("TextBox", {Text="2.45", Font=Enum.Font.Code, TextSize=11, TextColor3=THEME.accent2, BackgroundColor3=THEME.panel, BorderSizePixel=0, ClearTextOnFocus=false, TextXAlignment=Enum.TextXAlignment.Center, Position=UDim2.new(1,-50,0,3), Size=UDim2.fromOffset(44,18), ZIndex=3, Parent=sizeRow})
new("UICorner", {CornerRadius=UDim.new(0,3), Parent=sizeInput})
new("UIStroke", {Color=THEME.stroke, Thickness=1, Parent=sizeInput})
sizeInput:GetPropertyChangedSignal("Text"):Connect(function()
    local n = tonumber(sizeInput.Text)
    if n then HitboxSize = n; recomputeTargetSize() end
end)

local showBoxBtn = new("TextButton", {Text="SHOW BOX [ON]", Font=Enum.Font.GothamBold, TextSize=11, TextColor3=Color3.new(1,1,1), BackgroundColor3=THEME.accent, AutoButtonColor=false, Size=UDim2.new(1,0,0,24), LayoutOrder=3, ZIndex=2, Parent=content})
new("UICorner", {CornerRadius=UDim.new(0,4), Parent=showBoxBtn})
new("UIStroke", {Color=THEME.stroke, Thickness=1, Parent=showBoxBtn})
showBoxBtn.MouseButton1Click:Connect(function()
    showBoxEnabled = not showBoxEnabled
    if showBoxEnabled then
        showBoxBtn.Text = "SHOW BOX [ON]"
        showBoxBtn.BackgroundColor3 = THEME.accent
        showBoxBtn.TextColor3 = Color3.new(1,1,1)
    else
        showBoxBtn.Text = "SHOW BOX [OFF]"
        showBoxBtn.BackgroundColor3 = THEME.row
        showBoxBtn.TextColor3 = THEME.subtext
        for char, box in pairs(activeBoxes) do
            if box then box:Destroy() end
            activeBoxes[char] = nil
        end
    end
end)

local searchBar = new("TextBox", {
    Size=UDim2.new(1,0,0,24), BackgroundColor3=THEME.panel, BorderSizePixel=0,
    Text="Player Whitelist", Font=Enum.Font.Gotham, TextSize=11,
    TextColor3=THEME.subtext, ClearTextOnFocus=false,
    LayoutOrder=4, ZIndex=2, Parent=content})
new("UICorner", {CornerRadius=UDim.new(0,4), Parent=searchBar})
new("UIStroke", {Color=THEME.stroke, Thickness=1, Parent=searchBar})

local teamBar = new("TextBox", {
    Size=UDim2.new(1,0,0,24), BackgroundColor3=THEME.panel, BorderSizePixel=0,
    Text="Team Whitelist", Font=Enum.Font.Gotham, TextSize=11,
    TextColor3=THEME.subtext, ClearTextOnFocus=false,
    LayoutOrder=5, ZIndex=2, Parent=content})
new("UICorner", {CornerRadius=UDim.new(0,4), Parent=teamBar})
new("UIStroke", {Color=THEME.stroke, Thickness=1, Parent=teamBar})

local spacer = new("Frame", {Size=UDim2.new(1,0,0,5), BackgroundTransparency=1, LayoutOrder=6, Parent=content})

local floatToggleBtn = new("TextButton", {
    Text="HIDE FLOATING BUTTON", Font=Enum.Font.GothamBold, TextSize=10,
    TextColor3=Color3.new(1,1,1), BackgroundColor3=THEME.accent, AutoButtonColor=false,
    Size=UDim2.new(1,0,0,24), LayoutOrder=7, ZIndex=2, Parent=content})
new("UICorner", {CornerRadius=UDim.new(0,4), Parent=floatToggleBtn})
new("UIStroke", {Color=THEME.stroke, Thickness=1, Parent=floatToggleBtn})

local spacer2 = new("Frame", {Size=UDim2.new(1,0,0,5), BackgroundTransparency=1, LayoutOrder=8, Parent=content})

local clearPlayerBtn = new("TextButton", {
    Text="CLEAR PLAYER WL", Font=Enum.Font.GothamBold, TextSize=11,
    TextColor3=Color3.new(1,1,1), BackgroundColor3=THEME.bad, AutoButtonColor=false,
    Size=UDim2.new(1,0,0,24), LayoutOrder=9, ZIndex=2, Parent=content})
new("UICorner", {CornerRadius=UDim.new(0,4), Parent=clearPlayerBtn})

local clearTeamBtn = new("TextButton", {
    Text="CLEAR TEAM WL", Font=Enum.Font.GothamBold, TextSize=11,
    TextColor3=Color3.new(1,1,1), BackgroundColor3=THEME.bad, AutoButtonColor=false,
    Size=UDim2.new(1,0,0,24), LayoutOrder=10, ZIndex=2, Parent=content})
new("UICorner", {CornerRadius=UDim.new(0,4), Parent=clearTeamBtn})

floatBtn = new("TextButton", {
    Name="FloatBtn",
    Size=UDim2.fromOffset(70,70),
    AnchorPoint=Vector2.new(1, 0),
    Position=UDim2.new(1, -80, 0, 10),
    BackgroundColor3=THEME.bad,
    Text="HB OFF", Font=Enum.Font.GothamBlack, TextSize=12, TextColor3=Color3.new(1,1,1),
    AutoButtonColor=false, Visible=true, ZIndex=100, Parent=gui})
new("UICorner", {CornerRadius=UDim.new(1,0), Parent=floatBtn}) 
local fStroke = new("UIStroke", {Color=THEME.accent, Thickness=2, Parent=floatBtn})
new("UIGradient", {Color=ColorSequence.new{ColorSequenceKeypoint.new(0, THEME.accent), ColorSequenceKeypoint.new(1, THEME.accent2)}, Parent=fStroke})

local activeInput = nil
local dragStartPos = nil
local startPosF = nil
local isDragging = false

floatBtn.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
        activeInput = input
        dragStartPos = input.Position
        startPosF = floatBtn.Position
        isDragging = false
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if activeInput and input == activeInput then
        if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement then
            local delta = input.Position - dragStartPos
            if math.abs(delta.X) > 5 or math.abs(delta.Y) > 5 then
                isDragging = true
                floatBtn.Position = UDim2.new(startPosF.X.Scale, startPosF.X.Offset + delta.X, startPosF.Y.Scale, startPosF.Y.Offset + delta.Y)
            end
        end
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if activeInput and input == activeInput then
        if not isDragging then
            toggleAction()
        end
        activeInput = nil
    end
end)

local floatVisible = true
floatToggleBtn.MouseButton1Click:Connect(function()
    floatVisible = not floatVisible
    floatBtn.Visible = floatVisible
    if floatVisible then
        floatToggleBtn.Text = "HIDE FLOATING BUTTON"
        floatToggleBtn.BackgroundColor3 = THEME.accent
        floatToggleBtn.TextColor3 = Color3.new(1,1,1)
    else
        floatToggleBtn.Text = "SHOW FLOATING BUTTON"
        floatToggleBtn.BackgroundColor3 = THEME.panel
        floatToggleBtn.TextColor3 = THEME.subtext
    end
end)

local function showToast(text, color)
    local toast = new("TextLabel", {
        Size=UDim2.fromOffset(220, 30), Position=UDim2.new(0.5, -110, 0.85, 0),
        BackgroundColor3=color, TextColor3=Color3.new(1,1,1),
        Font=Enum.Font.GothamBold, TextSize=12, Text=text, ZIndex=999, Parent=gui})
    new("UICorner", {CornerRadius=UDim.new(0,6), Parent=toast})
    
    task.spawn(function()
        task.wait(2)
        TweenService:Create(toast, TweenInfo.new(0.4), {BackgroundTransparency=1, TextTransparency=1}):Play()
        task.wait(0.4)
        toast:Destroy()
    end)
end

searchBar.Focused:Connect(function()
    if searchBar.Text == "Player Whitelist" then
        searchBar.Text = ""
        searchBar.TextColor3 = THEME.text
    end
end)

searchBar.FocusLost:Connect(function(enterPressed)
    if searchBar.Text == "" then
        searchBar.Text = "Player Whitelist"
        searchBar.TextColor3 = THEME.subtext
        return
    end

    if enterPressed and searchBar.Text ~= "Player Whitelist" then
        local input = searchBar.Text:lower():gsub("%s+", "")
        if #input >= 3 then
            local foundInServer = false
            
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then
                    local uName = p.Name:lower()
                    local dName = p.DisplayName:lower()
                    
                    if uName:find(input, 1, true) or dName:find(input, 1, true) then
                        foundInServer = true
                        
                        if getgenv().CSTM_Whitelist[uName] or getgenv().CSTM_Whitelist[dName] then
                            showToast("Already Whitelisted", Color3.fromRGB(255, 165, 0))
                        else
                            getgenv().CSTM_Whitelist[uName] = true
                            getgenv().CSTM_Whitelist[dName] = true
                            saveWhitelist()
                            if p.Character then revertCharacter(p.Character) end
                            showToast("User Has Been Whitelisted", THEME.green)
                        end
                        break 
                    end
                end
            end
            
            if not foundInServer then
                if getgenv().CSTM_Whitelist[input] then
                    showToast("Already Whitelisted", Color3.fromRGB(255, 165, 0))
                else
                    getgenv().CSTM_Whitelist[input] = true
                    saveWhitelist()
                    showToast("User Has Been Whitelisted (Offline)", THEME.green)
                end
            end
        end
        
        searchBar.Text = "Player Whitelist"
        searchBar.TextColor3 = THEME.subtext
    end
end)

teamBar.Focused:Connect(function()
    if teamBar.Text == "Team Whitelist" then
        teamBar.Text = ""
        teamBar.TextColor3 = THEME.text
    end
end)

teamBar.FocusLost:Connect(function(enterPressed)
    if teamBar.Text == "" then
        teamBar.Text = "Team Whitelist"
        teamBar.TextColor3 = THEME.subtext
        return
    end

    if enterPressed and teamBar.Text ~= "Team Whitelist" then
        local raw = teamBar.Text:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if #raw >= 2 then
            if getgenv().CSTM_TeamWhitelist[raw] then
                showToast("Team Already Whitelisted", Color3.fromRGB(255, 165, 0))
            else
                getgenv().CSTM_TeamWhitelist[raw] = true
                saveWhitelist()

                local count = 0
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LocalPlayer and playerInTeamWL(p) then
                        count = count + 1
                        if p.Character then revertCharacter(p.Character) end
                    end
                end

                if count > 0 then
                    showToast("Team Whitelisted (" .. count .. " players)", THEME.green)
                else
                    showToast("Team Whitelisted (no match yet)", THEME.green)
                end
            end
        end

        teamBar.Text = "Team Whitelist"
        teamBar.TextColor3 = THEME.subtext
    end
end)

clearPlayerBtn.MouseButton1Click:Connect(function()
    getgenv().CSTM_Whitelist = {}
    saveWhitelist()
    showToast("Player WL Cleared", THEME.bad)
    
    if HitboxEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character and not playerInTeamWL(p) then 
                expandCharacter(p.Character) 
            end
        end
    end
end)

clearTeamBtn.MouseButton1Click:Connect(function()
    getgenv().CSTM_TeamWhitelist = {}
    saveWhitelist()
    showToast("Team WL Cleared", THEME.bad)
    
    if HitboxEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character and not getgenv().CSTM_Whitelist[p.Name:lower()] then 
                expandCharacter(p.Character) 
            end
        end
    end
end)

closeBtn.MouseButton1Click:Connect(function()
    revertAll()
    floatBtn:Destroy() 
    if hb then hb:Disconnect() end
    local tw = TweenService:Create(main, T_FAST, {Size=UDim2.fromOffset(0,0)})
    tw:Play(); tw.Completed:Wait()
    gui:Destroy()
end)

minimizeBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    if minimized then
        content.Visible = false
        minimizeBtn.Text = "+"
        TweenService:Create(main, TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size=UDim2.fromOffset(FINAL_SIZE.X.Offset, TOPBAR_H)}):Play()
    else
        TweenService:Create(main, TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size=FINAL_SIZE}):Play()
        minimizeBtn.Position = UDim2.new(1, -56, 0.5, -12)
        minimizeBtn.Text = "—"
        content.Visible = true
    end
end)

print("[F Society] CSTM + Team WL Loaded.")
