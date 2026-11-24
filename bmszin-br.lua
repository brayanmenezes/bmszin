-- LocalScript (StarterPlayerScripts)

local WindUI = loadstring(game:HttpGet("https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"))()
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local Camera = workspace.CurrentCamera

local player = Players.LocalPlayer
local highlightsAtivos = {}
local espLinhasAtivas = {}
local npcsCache = {} -- Guarda os NPCs para não lagar

-- Variáveis de Controle
local aimbotAtivo = false
local espAtivo = false
local toggleAimbotInterface = nil
local toggleESPInterface = nil

-- Variáveis de Teclas Padrão
local teclaAimbot = Enum.KeyCode.T
local teclaESP = Enum.KeyCode.G

-- Debounces
local ultimoToggleAimbot = 0
local ultimoToggleESP = 0
local ultimoToggleMenu = 0
local DEBOUNCE_TEMPO = 0.2

-- ==========================================
-- FUNÇÕES DE TIME E VERIFICAÇÃO
-- ==========================================
local function eAliado(p)
    if p == player then return true end
    -- Verifica por Time
    if player.Team and p.Team then
        return player.Team == p.Team
    end
    -- Verifica por Cor do Time (fallback)
    if player.TeamColor and p.TeamColor then
        return player.TeamColor == p.TeamColor
    end
    return false
end

-- Verifica se o modelo é um inimigo vivo (Jogador ou NPC)
local function eInimigoVivo(char)
    if not char or not char.Parent then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    -- Usa Head como fallback caso não tenha HumanoidRootPart (alguns jogos customizam)
    local partePrincipal = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
    
    if humanoid and humanoid.Health > 0 and partePrincipal then
        -- Se for um jogador, verifica se não é aliado
        local p = Players:GetPlayerFromCharacter(char)
        if p then
            return not eAliado(p)
        end
        -- Se não for jogador, é NPC (considera inimigo)
        return true
    end
    return false
end

-- ==========================================
-- SISTEMA DE VARREDURA (CACHE DE NPCs)
-- ==========================================
-- Roda a cada 1 segundo para achar NPCs escondidos em pastas sem lagar
task.spawn(function()
    while task.wait(1) do
        local novosNpcs = {}
        for _, obj in ipairs(workspace:GetDescendants()) do
            if obj:IsA("Model") and not Players:GetPlayerFromCharacter(obj) then
                local humanoid = obj:FindFirstChildOfClass("Humanoid")
                if humanoid and humanoid.Health > 0 then
                    table.insert(novosNpcs, obj)
                end
            end
        end
        npcsCache = novosNpcs
    end
end)

-- Pega todos os inimigos (jogadores + NPCs) em tempo real
local function obterTodosInimigos()
    local inimigos = {}
    
    -- 1. Jogadores
    for _, p in ipairs(Players:GetPlayers()) do
        if not eAliado(p) and p.Character and eInimigoVivo(p.Character) then
            table.insert(inimigos, p.Character)
        end
    end
    
    -- 2. NPCs (Puxados do Cache)
    for _, npc in ipairs(npcsCache) do
        if eInimigoVivo(npc) then
            table.insert(inimigos, npc)
        end
    end
    
    return inimigos
end

-- ==========================================
-- SISTEMA DE HIGHLIGHT + LINHAS (ESP)
-- ==========================================
local function criarESP(character)
    if highlightsAtivos[character] or espLinhasAtivas[character] then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local partePrincipal = character:FindFirstChild("HumanoidRootPart") or character:FindFirstChild("Head")
    if not humanoid or not partePrincipal then return end

    local highlight = Instance.new("Highlight")
    highlight.Name = "PvPHighlight"
    highlight.FillColor = Color3.fromRGB(255, 0, 0)
    highlight.OutlineColor = Color3.fromRGB(255, 0, 0)
    highlight.FillTransparency = 0.5
    highlight.OutlineTransparency = 0
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Adornee = character
    highlight.Parent = character
    highlightsAtivos[character] = highlight

    local line = Drawing.new("Line")
    line.Thickness = 2
    line.Color = Color3.fromRGB(255, 0, 0)
    line.Transparency = 1
    line.Visible = true
    
    espLinhasAtivas[character] = { Line = line, Parte = partePrincipal, Humanoid = humanoid }
end

local function removerESP(character)
    if highlightsAtivos[character] then
        highlightsAtivos[character]:Destroy()
        highlightsAtivos[character] = nil
    end
    if espLinhasAtivas[character] then
        espLinhasAtivas[character].Line:Remove()
        espLinhasAtivas[character] = nil
    end
end

local function removerTodos()
    for char, _ in pairs(highlightsAtivos) do removerESP(char) end
    highlightsAtivos = {}
    espLinhasAtivas = {}
end

-- ==========================================
-- ATUALIZAÇÃO EM TEMPO REAL (HEARTBEAT)
-- ==========================================
RunService.Heartbeat:Connect(function()
    if not espAtivo then return end

    local inimigosAtuais = obterTodosInimigos()
    local tabelaInimigos = {}
    
    -- Adiciona/Atualiza ESP
    for _, char in ipairs(inimigosAtuais) do
        tabelaInimigos[char] = true
        if not highlightsAtivos[char] then
            criarESP(char)
        else
            -- Atualiza a referência da parte principal caso o jogador tenha respawnado ou mudado de rig
            local novaParte = char:FindFirstChild("HumanoidRootPart") or char:FindFirstChild("Head")
            if novaParte and espLinhasAtivas[char] then
                espLinhasAtivas[char].Parte = novaParte
            end
        end
    end

    -- Remove ESP de quem morreu, saiu do time ou foi deletado
    for char, _ in pairs(highlightsAtivos) do
        if not tabelaInimigos[char] then
            removerESP(char)
        end
    end
end)

-- ==========================================
-- RENDERIZAÇÃO DAS LINHAS (RENDER STEPPED)
-- ==========================================
RunService.RenderStepped:Connect(function()
    for character, data in pairs(espLinhasAtivas) do
        local parte = data.Parte
        local humanoid = data.Humanoid
        local line = data.Line

        if parte and humanoid and humanoid.Health > 0 and character.Parent then
            local screenPos, onScreen = Camera:WorldToViewportPoint(parte.Position)
            if onScreen then
                line.From = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y)
                line.To = Vector2.new(screenPos.X, screenPos.Y)
                line.Visible = true
            else
                line.Visible = false
            end
        else
            line.Visible = false
            removerESP(character) -- Limpa imediatamente se bugar
        end
    end
end)

-- ==========================================
-- SISTEMA DE AIMBOT (TEMPO REAL)
-- ==========================================
local function pegarAlvoMaisProximo()
    local alvo = nil
    local menorDistancia = math.huge
    local centroTela = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)

    local inimigos = obterTodosInimigos()
    
    for _, char in ipairs(inimigos) do
        -- Usa a Cabeça para mirar (mais preciso)
        local head = char:FindFirstChild("Head")
        if head then
            local screenPos, onScreen = Camera:WorldToViewportPoint(head.Position)
            -- Se estiver na tela, calcula a distância
            if onScreen then
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - centroTela).Magnitude
                if dist < menorDistancia then
                    menorDistancia = dist
                    alvo = head
                end
            end
        end
    end
    return alvo
end

RunService.RenderStepped:Connect(function()
    if aimbotAtivo then
        local alvo = pegarAlvoMaisProximo()
        if alvo and alvo.Parent then
            local humanoid = alvo.Parent:FindFirstChildOfClass("Humanoid")
            if humanoid and humanoid.Health > 0 then
                Camera.CFrame = CFrame.lookAt(Camera.CFrame.Position, alvo.Position)
            end
        end
    end
end)

-- ==========================================
-- FUNÇÕES DE SINCRONIZAÇÃO DA INTERFACE
-- ==========================================
local function setAimbotState(state)
    aimbotAtivo = state
    if toggleAimbotInterface then toggleAimbotInterface:Set(state) end
end

local function setESPState(state)
    espAtivo = state
    if not state then removerTodos() end
    if toggleESPInterface then toggleESPInterface:Set(state) end
end

local function toggleAimbot()
    if tick() - ultimoToggleAimbot < DEBOUNCE_TEMPO then return end
    ultimoToggleAimbot = tick()
    setAimbotState(not aimbotAtivo)
end

local function toggleESP()
    if tick() - ultimoToggleESP < DEBOUNCE_TEMPO then return end
    ultimoToggleESP = tick()
    setESPState(not espAtivo)
end

local function converterTecla(tecla)
    if typeof(tecla) == "EnumItem" then return tecla end
    if type(tecla) == "string" then
        local success, keycode = pcall(function() return Enum.KeyCode[tecla] end)
        if success then return keycode end
    end
    return nil
end

-- ==========================================
-- INTERFACE (WindUI)
-- ==========================================
local Window = WindUI:CreateWindow({
    Title = "BMSZIN 🐱‍👤",
    Icon = "swords",
    Author = "É OS BR 🇧🇷",
    Folder = "BMSZIN",
    Size = UDim2.fromOffset(420, 320),
})

local Tab = Window:Tab({ Title = "PvP", Icon = "swords" })

-- Toggle ESP
toggleESPInterface = Tab:Toggle({
    Title = "Ativar Highlight e ESP",
    Desc = "Aplica destaque e linha nos inimigos",
    Value = false,
    Callback = function(state)
        if espAtivo == state then return end
        setESPState(state)
    end,
})

-- Keybind ESP
Tab:Keybind({
    Title = "Atalho do ESP",
    Desc = "Escolha a tecla para ligar/desligar o ESP",
    Value = "G",
    Callback = function(tecla)
        local key = converterTecla(tecla)
        if key then
            teclaESP = key
            pcall(function() ContextActionService:UnbindAction("ToggleESP_BMSZIN") end)
            ContextActionService:BindActionAtPriority("ToggleESP_BMSZIN", function(_, state, _)
                if state == Enum.UserInputState.Begin then toggleESP() end
                return Enum.ContextActionResult.Pass
            end, false, Enum.ContextActionPriority.High.Value, teclaESP)
        end
    end,
})

Tab:Divider()

-- Toggle Aimbot
toggleAimbotInterface = Tab:Toggle({
    Title = "Ativar Aimbot",
    Desc = "Mira automaticamente no inimigo",
    Value = false,
    Callback = function(state)
        if aimbotAtivo == state then return end
        setAimbotState(state)
    end,
})

-- Keybind Aimbot
Tab:Keybind({
    Title = "Atalho do Aimbot",
    Desc = "Escolha a tecla para ligar/desligar o Aimbot",
    Value = "T",
    Callback = function(tecla)
        local key = converterTecla(tecla)
        if key then
            teclaAimbot = key
            pcall(function() ContextActionService:UnbindAction("ToggleAimbot_BMSZIN") end)
            ContextActionService:BindActionAtPriority("ToggleAimbot_BMSZIN", function(_, state, _)
                if state == Enum.UserInputState.Begin then toggleAimbot() end
                return Enum.ContextActionResult.Pass
            end, false, Enum.ContextActionPriority.High.Value, teclaAimbot)
        end
    end,
})

-- ==========================================
-- CONTROLE DO MENU (CTRL) E BINDS INICIAIS
-- ==========================================
local function toggleMenu()
    if tick() - ultimoToggleMenu < DEBOUNCE_TEMPO then return end
    ultimoToggleMenu = tick()
    pcall(function() Window:Toggle() end)
end

pcall(function() ContextActionService:UnbindAction("ToggleAimbot_BMSZIN") end)
ContextActionService:BindActionAtPriority("ToggleAimbot_BMSZIN", function(_, state, _)
    if state == Enum.UserInputState.Begin then toggleAimbot() end
    return Enum.ContextActionResult.Pass
end, false, Enum.ContextActionPriority.High.Value, teclaAimbot)

pcall(function() ContextActionService:UnbindAction("ToggleESP_BMSZIN") end)
ContextActionService:BindActionAtPriority("ToggleESP_BMSZIN", function(_, state, _)
    if state == Enum.UserInputState.Begin then toggleESP() end
    return Enum.ContextActionResult.Pass
end, false, Enum.ContextActionPriority.High.Value, teclaESP)

pcall(function() ContextActionService:UnbindAction("ToggleMenu_BMSZIN") end)
ContextActionService:BindActionAtPriority("ToggleMenu_BMSZIN", function(_, state, _)
    if state == Enum.UserInputState.Begin then toggleMenu() end
    return Enum.ContextActionResult.Pass
end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl)

-- Fallback de segurança
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if UserInputService:GetFocusedTextBox() then return end
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
            toggleMenu()
        elseif input.KeyCode == teclaAimbot then
            toggleAimbot()
        elseif input.KeyCode == teclaESP then
            toggleESP()
        end
    end
end)