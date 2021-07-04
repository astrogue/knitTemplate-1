-- Comm
-- EncodedVenom
-- July 1, 2021

--[[
    I don't know how EventHandlers are defined in lua syntax so I opted for Java syntax.

    Comnm.new(Component: Component, ComponentInstance: Instance, Maid: Maid): Comm

    Comm:BindEvent(EventName: string): void
    Comm:BindEventRaw(EventName: string, @EventHandler): void
        This is the function that BindEvent uses to handle events. Use this if you do not like components being used directly and would rather pass a callback.

    Server:
        Comm:BindFunction(BoundFunctionName: string): void
        Comm:BindFunctionRaw(BoundFunctionName: string, @InvokeHandler): void
            Exists for the same reason as BindEventRaw except for the RemoteFunction variant.

        Comm:CreateEvent(EventName: string): void
        Comm:FireClient(TargetPlayer: Player, EventName: string, ...args: any): void
        Comm:FireAllClients(EventName: string, ...args: any): void
        Comm:FireAllClientsExcept(PlayerToExclude: Player, EventName: string, ...args: any): void

    Client:
        Comm:FireServer(EventName: string, ...args: any): void
        Comm:InvokeServer(FunctionName: string, ...args: any): any
]]

local Players = game:GetService("Players")

local IS_SERVER = game:GetService("RunService"):IsServer()
local EVENT_ALREADY_CREATED = "RemoteEvent \"%s\" already exists!"
local FUNCTION_ALREADY_CREATED = "RemoteFunction \"%s\" already exists!"
local EVENT_UNDEF = "The event \"%s\" is not defined on the %s component!"
local EVENT_IMPROPER_REF = "\"%s\" is not a valid RemoteEvent!"
local FUNCTION_IMPROPER_REF = "\"%s\" is not a valid RemoteFunction!"
local CALLED_ON_WRONG_SIDE = "\"%s\" cannot be called on the %s!"
local REMOTE_CREATION_FAILURE = "The Remotes folder for this component does not exist."
local SERVER_OR_CLIENT_EVENT = IS_SERVER and "OnServerEvent" or "OnClientEvent"

local Comm = {}
Comm.__index = Comm

function Comm.new(Component, ComponentInstance, Maid)
    local Remotes = ComponentInstance:FindFirstChild("Remotes");
    local ComponentRemotes;
    if IS_SERVER then
        if not Remotes then
            Remotes = Instance.new("Folder", ComponentInstance)
            Remotes.Name = "Remotes"
        end
        ComponentRemotes = Instance.new("Folder", Remotes)
        ComponentRemotes.Name = Component.Tag
        Maid:GiveTask(function()
            ComponentRemotes:Destroy()
            if #Remotes:GetChildren() == 0 then
                Remotes:Destroy()
            end
        end)
    else
        if not Remotes then
            Remotes = ComponentInstance:WaitForChild("Remotes", 2) -- This may not be needed, but I found issues without this line. Better safe than sorry.
        end
        ComponentRemotes = Remotes:WaitForChild(Component.Tag, 2)
    end
    if not ComponentRemotes then error(REMOTE_CREATION_FAILURE) return end
    local self = setmetatable({
        _component = Component;
        _instance = ComponentInstance;
        _maid = Maid;
        _remotesFolder = ComponentRemotes;
    }, Comm)
    self._maid:GiveTask(self)
    return self
end

function Comm:BindFunction(BoundFunctionName: string)
    assert(self._component[BoundFunctionName] ~= nil, "The component must have "..BoundFunctionName.." as a function.")
    self:BindFunctionRaw(BoundFunctionName, function(...)
        return self._component[BoundFunctionName](self._component, ...)
    end)
end

function Comm:BindFunctionRaw(BoundFunctionName: string, InvokeHandler)
    if not IS_SERVER then error(CALLED_ON_WRONG_SIDE:format("BindFunction", "client")) return end
    assert((BoundFunctionName ~= nil) and (typeof(BoundFunctionName)=="string"), "BoundFunctionName must be a valid string")
    assert((InvokeHandler ~= nil) and (typeof(InvokeHandler)=="function"), "InvokeHandler must be a valid function")
    if self._remotesFolder:FindFirstChild(BoundFunctionName) then warn(FUNCTION_ALREADY_CREATED:format(BoundFunctionName)) return end
    local RF: RemoteFunction = Instance.new("RemoteFunction", self._remotesFolder)
    RF.Name = BoundFunctionName
    RF.OnServerInvoke = InvokeHandler
    self._maid:GiveTask(RF)
end

function Comm:CreateEvent(EventName: string)
    if not IS_SERVER then error(CALLED_ON_WRONG_SIDE:format("CreateEvent", "client")) return end
    assert((EventName ~= nil) and (typeof(EventName)=="string"), "EventName must be a valid string")
    if self._remotesFolder:FindFirstChild(EventName) then warn(EVENT_ALREADY_CREATED:format(EventName)) return end
    local RE: RemoteEvent = Instance.new("RemoteEvent", self._remotesFolder)
    RE.Name = EventName
    self._maid:GiveTask(RE)
end

function Comm:BindEvent(EventName: string)
    assert(self._component[EventName] ~= nil, "The component must have "..EventName.." as an event handler.")
    self:BindEventRaw(EventName, function(...)
        self._component[EventName](self._component, ...)
    end)
end

function Comm:BindEventRaw(EventName: string, EventHandler)
    assert((EventName ~= nil) and (typeof(EventName)=="string"), "EventName must be a valid string")
    assert((EventHandler ~= nil) and (typeof(EventHandler)=="function"), "EventHandler must be a valid function")
    if not self._component[EventName] then error(EVENT_UNDEF:format(EventName, IS_SERVER and "server" or "client")) return end
    local Remote: RemoteEvent = self._remotesFolder:WaitForChild(EventName, 5)
    if not Remote then error(EVENT_IMPROPER_REF:format(EventName)) return end
    local Signal: RBXScriptSignal = Remote[SERVER_OR_CLIENT_EVENT]
    self._maid:GiveTask(Signal:Connect(EventHandler))
end

function Comm:FireClient(TargetPlayer: Player, EventName: string, ...)
    if not IS_SERVER then error(CALLED_ON_WRONG_SIDE:format("FireClient", "client")) return end
    assert((TargetPlayer ~= nil) and (TargetPlayer:IsDescendantOf(Players)), "TargetPlayer must be a valid Player")
    local Event: RemoteEvent = self._remotesFolder:FindFirstChild(EventName)
    if (not Event) or (not Event:IsA("RemoteEvent")) then error(EVENT_IMPROPER_REF:format(EventName)) return end
    Event:FireClient(TargetPlayer, ...)
end

function Comm:FireAllClients(EventName: string, ...)
    if not IS_SERVER then error(CALLED_ON_WRONG_SIDE:format("FireAllClients", "client")) return end
    assert((EventName ~= nil) and (typeof(EventName)=="string"), "EventName must be a valid string")
    local Event: RemoteEvent = self._remotesFolder:FindFirstChild(EventName)
    if (not Event) or (not Event:IsA("RemoteEvent")) then error(EVENT_IMPROPER_REF:format(EventName)) return end
    Event:FireAllClients(...)
end

function Comm:FireAllClientsExcept(PlayerToExclude: Player, EventName: string, ...)
    if not IS_SERVER then error(CALLED_ON_WRONG_SIDE:format("FireAllClientsExcept", "client")) return end
    assert((PlayerToExclude ~= nil) and (PlayerToExclude:IsDescendantOf(Players)), "PlayerToExclude must be a valid Player")
    assert((EventName ~= nil) and (typeof(EventName)=="string"), "EventName must be a valid string")
    local Event: RemoteEvent = self._remotesFolder:FindFirstChild(EventName)
    if (not Event) or (not Event:IsA("RemoteEvent")) then error(EVENT_IMPROPER_REF:format(EventName)) return end
    for _, Player in pairs(Players:GetPlayers()) do
        if Player == PlayerToExclude then continue end
        Event:FireClient(Player, ...)
    end
end

function Comm:FireServer(EventName: string, ...)
    if IS_SERVER then error(CALLED_ON_WRONG_SIDE:format("FireServer", "server")) return end
    assert((EventName ~= nil) and (typeof(EventName)=="string"), "EventName must be a valid string")
    local Event: RemoteEvent = self._remotesFolder:WaitForChild(EventName, 5)
    if (not Event) or (not Event:IsA("RemoteEvent")) then error(EVENT_IMPROPER_REF:format(EventName)) return end
    Event:FireServer(...)
end

function Comm:InvokeServer(FunctionName: string, ...)
    assert((FunctionName ~= nil) and (typeof(FunctionName)=="string"), "FunctionName must be a valid string")
    if IS_SERVER then error(CALLED_ON_WRONG_SIDE:format("InvokeServer", "server")) return end
    local Function: RemoteFunction = self._remotesFolder:WaitForChild(FunctionName, 5)
    if (not Function) or (not Function:IsA("RemoteFunction")) then error(FUNCTION_IMPROPER_REF:format(FunctionName)) return end
    return Function:InvokeServer(...)
end

function Comm:Destroy()
    self = nil
end

return Comm