--!strict

--[[
 _____ _     _  __ _   _   _       _            _            _ 
/  ___| |   (_)/ _| | | | | |     | |          | |          | |
\ `--.| |__  _| |_| |_| | | |_ __ | | ___   ___| | _____  __| |
 `--. \ '_ \| |  _| __| | | | '_ \| |/ _ \ / __| |/ / _ \/ _` |
/\__/ / | | | | | | |_| |_| | | | | | (_) | (__|   <  __/ (_| |
\____/|_| |_|_|_|  \__|\___/|_| |_|_|\___/ \___|_|\_\___|\__,_|
                                                                                                                                  
         -- A Third-Person Camera for the Roblox Engine --     
    -- made by Yiannis123 credit would be appreciated if used -- 
-- Based on ShoulderCam Roblox module and Roblox PlayerModule Source -- 
]]

debug.setmemorycategory("SUCamera")

--// Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

--// Modules
local JanitorModule = require(script.Parent.janitor)
local SmartRaycast = require(script.Parent.smartraycast)
local Popper = require(script.ForkedPopper)
local ConstrainedSpring = require(script.ConstrainedSpring)
local Vector3Spring = require(script.Vector3Spring)
local CameraShakeInstance = require(script.CameraShakeInstance)
local CameraShakePresets = require(script.CameraShakePresets)

--// Variables
local LocalPlayer = Players.LocalPlayer
local GameSettings = UserSettings().GameSettings -- Updates RealTime
local InternalChannelName = HttpService:GenerateGUID() -- This is done so we don't collide with any other user channels
local CameraShakeState = CameraShakeInstance.CameraShakeState

--// Global Settings Defualt Values
local GCWarn = true
local GlobalRaycastChannelName = InternalChannelName
local AutoExcludeChars = true
local CameraShakeDefaultPosInfluence = Vector3.new(0.15, 0.15, 0.15)
local CameraShakeDefaultRotInfluence = Vector3.new(1, 1, 1)

--// Gamepad thumbstick utilities //--

-- k (positive input) and LowerK (negative input) control thumbstick sensitivity; lower values for more responsive extremes, higher values for smoother, more linear control
-- Adjust these values based on your needs
-- Current setup has more precise postive value control and fast negative value control
-- This values are adjusted at runtime based on currently active SU camera settings

local K = 0.5 -- A higher k value makes the curve more linear. A lower k makes it more curved and accelerating
local LowerK = 0.9 -- Same as k, but controls the lower portion of the S-curve for negative input values
local Deadzone = 0.25 -- this specifies the range of input values near 0 that will be mapped to 0 output. This creates a "deadzone" in the middle to prevent unintentional input.

local function SCurveTransform(t: number)
	t = math.clamp(t, -1, 1)
	if t >= 0 then
		return (K * t) / (K - t + 1)
	end
	return -((LowerK * -t) / (LowerK + t + 1))
end

local function ToSCurveSpace(t: number)
	return (1 + Deadzone) * (2 * math.abs(t) - 1) - Deadzone
end

local function FromSCurveSpace(t: number)
	return t / 2 + 0.5
end

-- Applies a nonlinear transform to the thumbstick position to serve as the acceleration for camera rotation.
-- See https://www.desmos.com/calculator/xw2ytjpzco for a visual reference.
local function GamepadLinearToCurve(ThumbstickPosition)
	return Vector2.new(
		math.clamp(
			math.sign(ThumbstickPosition.X)
				* FromSCurveSpace(SCurveTransform(ToSCurveSpace(math.abs(ThumbstickPosition.X)))),
			-1,
			1
		),
		math.clamp(
			math.sign(ThumbstickPosition.Y)
				* FromSCurveSpace(SCurveTransform(ToSCurveSpace(math.abs(ThumbstickPosition.Y)))),
			-1,
			1
		)
	)
end

--// ShiftUnlocked Camera //--

local CoreZoom = 12.5

RunService:BindToRenderStep("CoreZoomUpdater", Enum.RenderPriority.Camera.Value + 1, function()
	if game.Workspace.CurrentCamera and game.Workspace.CurrentCamera.CameraType == Enum.CameraType.Custom then
		CoreZoom = (game.Workspace.CurrentCamera.Focus.Position - game.Workspace.CurrentCamera.CFrame.Position).Magnitude
	end
end)

function CreateMouseIconGui(): { Gui: ScreenGui, Frame: Frame, Icon: ImageLabel }
	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Enabled = false
	ScreenGui.Name = "ShiftUnlockedControllerMouseIconUI"
	ScreenGui.IgnoreGuiInset = true
	ScreenGui.ResetOnSpawn = false

	local Frame = Instance.new("Frame")
	Frame.Size = UDim2.new(1, 0, 1, 0)
	Frame.BackgroundTransparency = 1
	Frame.Parent = ScreenGui

	local ImageLabel = Instance.new("ImageLabel")
	ImageLabel.BackgroundTransparency = 1
	ImageLabel.Size = UDim2.new(0, 32, 0, 32)
	ImageLabel.Position = UDim2.new(0.5, -ImageLabel.Size.X.Offset / 2, 0.5, -ImageLabel.Size.Y.Offset / 2)
	ImageLabel.Parent = Frame

	ScreenGui.Parent = LocalPlayer.PlayerGui

	return {
		Gui = ScreenGui,
		Frame = Frame,
		Icon = ImageLabel,
	}
end

local SUCamera = {}
SUCamera.__index = SUCamera

SUCamera.GCWarn = GCWarn
SUCamera.GlobalRaycastChannelName = GlobalRaycastChannelName
SUCamera.AutoExcludeChars = AutoExcludeChars
SUCamera.CameraShakeInstance = CameraShakeInstance
SUCamera.CameraShakePresets = CameraShakePresets
SUCamera.CameraShakeDefaultPosInfluence = CameraShakeDefaultPosInfluence
SUCamera.CameraShakeDefaultRotInfluence = CameraShakeDefaultRotInfluence

type SUCameraProperties = {
	FOV: number,
	_Enabled: boolean,
	_Janitor: JanitorModule.Janitor,
	LockedIcon: string?,
	UnlockedIcon: string?,
	AdjustedControllerIconDisplay: boolean,
	_HidingMouseIcon: boolean,
	PitchLimit: number,
	_Yaw: number,
	_Pitch: number,
	MouseRadsPerPixel: Vector2,
	_GamepadPan: Vector2,
	_LastThumbstickTime: number,
	_LastThumbstickPos: Vector2,
	GamepadSensitivityModifier: Vector2,
	TouchSensitivityModifier: Vector2,
	GamepadKValue: number,
	GamepadLowerKValue: number,
	GamepadDeadzone: number,
	_CurrentGamepadSpeed: number,
	_LastGamepadVelocity: Vector2,
	CameraOffset: Vector3,
	_CurrentRootPart: BasePart?,
	_CurrentCamera: Camera?,
	RaycastChannel: SmartRaycast.Channel | nil,
	MouseLocked: boolean,
	_CurrentHumanoid: Humanoid | nil,
	_CurrentCFrame: CFrame,
	ObstructionRange: number,
	_LastDistanceFromRoot: number,
	_CollisionRadius: number,
	RotateCharacter: boolean,
	VelocityOffset: boolean,
	AllowVelocityOffsetOnTeleport: boolean,
	VelocityOffsetFrequency: number,
	VelocityOffsetDamping: number,
	VelocityOffsetVelocityThreshold: number,
	_Vector3Spring: Vector3Spring.Vector3Spring,
	_V3SpringConcluded: boolean,
	_LastFocusPosition: Vector3?,
	_LastRootPartPosition: Vector3?,
	_LastCharacterVelocity: Vector3?,
	_TeleportationThreshold: number,
	MaxZoom: number,
	MinZoom: number,
	StartZoom: number,
	ZoomLocked: boolean,
	ZoomControllerKey: Enum.KeyCode?,
	ZoomInKeyboardKey: Enum.KeyCode?,
	ZoomOutKeyboardKey: Enum.KeyCode?,
	_ZoomInKeyDown: boolean,
	_ZoomOutKeyDown: boolean,
	_ZoomSpring: ConstrainedSpring.ConstrainedSpring,
	_ControllerZoomCycleInverted: boolean,
	ZoomStiffness: number,
	ZoomSpeedMouse: number,
	ZoomSpeedTouch: number,
	ZoomSpeedKeyboard: number,
	ZoomSensitivityCurvature: number,
	TimeUntilCorrectionReversion: number,
	CorrectionReversionSpeed: number,
	_YAxisCorrectionValues: {
		LastCorrectionReturned: number,
		LastMangitude: number,
		Time0Preserved: number,
		LastCorrection: number,
	},
	_XAxisCorrectionValues: {
		LastCorrectionReturned: number,
		LastMangitude: number,
		Time0Preserved: number,
		LastCorrection: number,
	},
	_ZAxisCorrectionValues: {
		LastCorrectionReturned: number,
		LastMangitude: number,
		Time0Preserved: number,
		LastCorrection: number,
	},
	_ZoomCorrectionValues: {
		LastCorrectionReturned: number,
		LastMangitude: number,
		Time0Preserved: number,
		LastCorrection: number,
	},
	CorrectionReversion: boolean,
	_ZoomState: string,
	_CurrentCorrectedZoom: number,
	_CamShakeInstances: { CameraShakeInstance.CameraShakeInstance },
	_CamShakeInstancesToRemove: { number },
	_SavedCursor: string,
	_CustomMouseIconGUIInstances: { Gui: ScreenGui, Frame: Frame, Icon: ImageLabel },
	_CurrentInputMethod: string,
	_ActiveTouchInputs: { InputObject },
	_LastPinchDiameter: number?,
	FreeCamMode: boolean,
	FreeCamCFrame: CFrame,
	SyncZoom: boolean,
	_SyncingZoom: boolean,
	_CharacterOverriden: boolean,
	_CharacterOverride: Instance?,
}

export type SUCamera = typeof(setmetatable({} :: SUCameraProperties, SUCamera))

local CameraLog: { SUCamera } = {}

--// Camera Conctructor //--

function SUCamera.new(): SUCamera
	local self = setmetatable({} :: SUCameraProperties, SUCamera)

	-- Configurable Parameters

	self.FOV = 70 -- Camera FOV gets automaticly clamped to 1 - 120
	self.PitchLimit = 70 -- the max degrees the camera can angle up and down
	self.LockedIcon = "rbxasset://textures/MouseLockedCursor.png"
	self.UnlockedIcon = nil
	self.MouseLocked = true
	self.MouseRadsPerPixel = Vector2.new(0.00872664619, 0.00671951752) -- dont worry to much about this setting
	self.GamepadSensitivityModifier = Vector2.new(0.85, 0.65)
	self.TouchSensitivityModifier = Vector2.new(1 / 100, 1 / 100)
	self.GamepadLowerKValue = 0.9
	self.GamepadKValue = 0.5
	self.GamepadDeadzone = 0.25
	self.CameraOffset = Vector3.new(1.75, 1.5, 0) -- (legay value 1.75,1.5,0)
	self.RaycastChannel = nil
	self.ObstructionRange = 6.5 -- Distance from the camera required to start making the local character transparent
	self.RotateCharacter = true
	self.VelocityOffset = true
	self.AllowVelocityOffsetOnTeleport = false
	self.VelocityOffsetFrequency = 9.5
	self.VelocityOffsetDamping = 0.75
	self.VelocityOffsetVelocityThreshold = 0.45
	self.ZoomLocked = false
	self.StartZoom = 12.5
	self.MaxZoom = 400
	self.MinZoom = 2
	self.ZoomStiffness = 4.5
	self.ZoomSpeedMouse = 1
	self.ZoomSpeedKeyboard = 0.1
	self.ZoomSpeedTouch = 0.04
	self.ZoomSensitivityCurvature = 0.5
	self.ZoomControllerKey = Enum.KeyCode.ButtonR3
	self.ZoomInKeyboardKey = Enum.KeyCode.I
	self.ZoomOutKeyboardKey = Enum.KeyCode.O
	self.TimeUntilCorrectionReversion = 0.8
	self.CorrectionReversionSpeed = 2.5
	self.CorrectionReversion = true
	self.FreeCamMode = false
	self.FreeCamCFrame = CFrame.new()
	self.SyncZoom = false
	self.AdjustedControllerIconDisplay = false

	-- Camera State Variables

	self._Enabled = false
	self._Pitch = 0
	self._Yaw = 0
	self._CurrentCFrame = CFrame.new()
	self._CollisionRadius = self:_GetCollisionRadius()
	self._ZoomState = "Neutral"
	self._ControllerZoomCycleInverted = false
	self._CurrentInputMethod = self:_GetCurrentInputMethod()
	self._ZoomInKeyDown = false
	self._ZoomOutKeyDown = false
	self._ActiveTouchInputs = {}
	self._LastPinchDiameter = nil
	self._SyncingZoom = false
	self._CharacterOverriden = false
	self._HidingMouseIcon = false

	-- Velocty Offset

	self._V3SpringConcluded = true
	self._LastFocusPosition = nil
	self._LastRootPartPosition = nil
	self._LastCharacterVelocity = nil
	self._TeleportationThreshold = 500 -- % increase since last frame to be considered teleporation

	-- Occlusion / Focus Collision

	self._LastDistanceFromRoot = 0
	self._YAxisCorrectionValues =
		{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
	self._XAxisCorrectionValues =
		{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
	self._ZAxisCorrectionValues =
		{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
	self._ZoomCorrectionValues =
		{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
	self._CurrentCorrectedZoom = self.StartZoom

	-- Gamepad Variables

	self._GamepadPan = Vector2.new(0, 0)
	self._LastThumbstickTime = 0
	self._LastThumbstickPos = Vector2.new(0, 0)
	self._CurrentGamepadSpeed = 0
	self._LastGamepadVelocity = Vector2.new(0, 0)

	-- DataModel refrences

	self._Janitor = JanitorModule.new()
	self._ZoomSpring = ConstrainedSpring.new(self.ZoomStiffness, self.StartZoom, self.MinZoom, self.MaxZoom)
	self._Vector3Spring = Vector3Spring.new(self.VelocityOffsetFrequency, self.VelocityOffsetDamping)
	self._CurrentRootPart = nil
	self._CurrentHumanoid = nil
	self._CurrentCamera = nil
	self._CamShakeInstances = {}
	self._CamShakeInstancesToRemove = {}
	self._SavedCursor = UserInputService.MouseIcon
	self._CustomMouseIconGUIInstances = CreateMouseIconGui()
	self._CharacterOverride = nil

	-- Insert SUCamera to CameraLog table

	table.insert(CameraLog, self)

	-- Perform Memory leak check if GCWarn is active

	if GCWarn == true and #CameraLog > 1 then
		warn(
			"[ShiftUnlocked] There are currently "
				.. tostring(#CameraLog)
				.. " SUCameras, there might be a memory leak in your code (Set GCWarn to false to stop this warning from appearing)"
		)
	end

	return self
end

--// Camera Enable Method //--

function SUCamera.SetEnabled(self: SUCamera, Enabled: boolean)
	if Enabled == self._Enabled then
		-- No need to perform any action:
		return
	end

	if self._Enabled == false then
		-- Make sure that other cameras are not enabled

		if #CameraLog > 1 then
			for _, Cam in CameraLog do
				assert(not Cam._Enabled, "[ShiftUnlocked] There are more than one SUCameras enabled currently")
			end
		end

		if self.RaycastChannel == nil then
			-- RaycastChannel property is undefined we fallback to global channel:

			if SmartRaycast.GetChannel(self.GlobalRaycastChannelName) == nil then
				-- Global channel needs to be created by the module (defualt behavior)
				SmartRaycast.CreateChannel(self.GlobalRaycastChannelName, nil, function(Inst)
					if Inst.Transparency == 1 or Inst.CanCollide == false then
						return true
					end
					return false
				end, Enum.RaycastFilterType.Exclude)
			end

			self.RaycastChannel = SmartRaycast.GetChannel(self.GlobalRaycastChannelName) :: SmartRaycast.Channel
		end

		-- Record the mouse icon before camera was enabled

		self._SavedCursor = UserInputService.MouseIcon

		-- Set Popper's ActiveSUCamera value

		Popper.ActiveSUCamera = self :: any -- Avoid typecheck issue due it expecting a nil value

		-- Enable Popper

		Popper.SetEnabled(true)

		-- Bind camera zoom keyboard input function to render stepped

		RunService:BindToRenderStep("SUCameraKeyboardZoom", Enum.RenderPriority.Camera.Value - 2, function()
			self:_KeyboardZoomStep()
		end)

		-- Bind camera update function to render stepped

		RunService:BindToRenderStep("SUCameraUpdate", Enum.RenderPriority.Camera.Value - 1, function(DT)
			self:_Update(DT)
		end)

		-- Connect Input Events

		self._Janitor:Add(
			UserInputService.InputBegan:Connect(function(InputObject: InputObject, GameProccessed: boolean)
				self:_OnInputBegun(InputObject, GameProccessed)
			end),
			"Disconnect"
		)

		self._Janitor:Add(
			UserInputService.InputEnded:Connect(function(InputObject: InputObject, GameProccessed: boolean)
				self:_OnInputEnded(InputObject, GameProccessed)
			end),
			"Disconnect"
		)

		self._Janitor:Add(
			UserInputService.InputChanged:Connect(function(InputObject: InputObject, GameProccessed: boolean)
				self:_OnInputChanged(InputObject, GameProccessed)
			end),
			"Disconnect"
		)

		self._Janitor:Add(
			UserInputService.PointerAction:Connect(
				function(Wheel: number, Pan: Vector2, Pinch: number, GameProccessed: boolean)
					self:_OnMouseZoomInput(Wheel, Pan, Pinch, GameProccessed)
				end
			),
			"Disconnect"
		)

		self._Janitor:Add(
			UserInputService.LastInputTypeChanged:Connect(function(InputType: Enum.UserInputType)
				self:_OnInputTypeChanged(InputType)
			end),
			"Disconnect"
		)

		-- Connect Character Events

		self._Janitor:Add(
			LocalPlayer.CharacterAdded:Connect(function(Character: Instance?)
				if self._CharacterOverriden == true then
					-- Character is overriden local character should not be used:
					return
				end

				self:_OnCurrentCharacterChanged(Character)
			end),
			"Disconnect"
		)

		self._Janitor:Add(
			LocalPlayer.CharacterRemoving:Connect(function()
				if self._CharacterOverriden == true then
					-- Character is overriden local character should not be used:
					return
				end

				self:_OnCurrentCharacterChanged(nil)
			end),
			"Disconnect"
		)

		-- Connect CurrentCamera Event

		self._Janitor:Add(
			workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
				self:_CurrentCameraChanged(workspace.CurrentCamera)
			end),
			"Disconnect"
		)

		-- Connect Global Character Exclusion events

		local RaycastChannel = self.RaycastChannel :: SmartRaycast.Channel

		if
			self.AutoExcludeChars == true
			and RaycastChannel.RaycastParams.FilterType == Enum.RaycastFilterType.Exclude
		then
			local function CharacterAdded(Character)
				RaycastChannel:AddToFilter(Character)
			end

			local function PlayerAdded(Player: Player)
				self._Janitor:Add(Player.CharacterAdded:Connect(CharacterAdded), "Disconnect", tostring(Player.UserId))
			end

			local function PlayerRemoving(Player: Player)
				self._Janitor:Remove(tostring(Player.UserId))
			end

			for _, Player in Players:GetPlayers() do
				PlayerAdded(Player)
				if Player.Character then
					RaycastChannel:AddToFilter(Player.Character)
				end
			end

			self._Janitor:Add(Players.PlayerAdded:Connect(PlayerAdded), "Disconnect")
			self._Janitor:Add(Players.PlayerRemoving:Connect(PlayerRemoving), "Disconnect")
		end

		-- Init/Reset Zoom Spring (We need to do this before we set the camera type)

		if self.SyncZoom == true then
			local StartZoom = math.clamp(CoreZoom, self.MinZoom, self.MaxZoom)

			self._ZoomSpring.CurrentPos = StartZoom
			self._ZoomSpring.Goal = StartZoom
		else
			self._ZoomSpring.CurrentPos = self.StartZoom
			self._ZoomSpring.Goal = self.StartZoom
		end

		self._ZoomSpring.CurrentVelocity = 0

		-- Run '_CurrentCameraChanged' and '_OnCurrentCharacterChanged'

		self:_OnCurrentCharacterChanged(
			self._CharacterOverriden == false and LocalPlayer.Character or self._CharacterOverride
		)
		self:_CurrentCameraChanged(workspace.CurrentCamera)

		-- Make transition to custom camera smooth by facing in same direction as previous camera

		local CameraLook = (self._CurrentCamera :: Camera).CFrame.LookVector

		self._Yaw = math.atan2(-CameraLook.X, -CameraLook.Z)
		self._Pitch = math.asin(CameraLook.Y)

		-- Init current input method

		self._CurrentInputMethod = self:_GetCurrentInputMethod()
	else
		-- Sync the Core Camera zoom with the SUCamera zoom (Needs to be done while the camera is active)

		if self.SyncZoom == true then
			self._SyncingZoom = true
			self._ZoomSpring.Goal = CoreZoom

			while
				not (self._CurrentRootPart == nil or self._CurrentCamera == nil or self._CurrentHumanoid == nil)
				and math.abs(self._ZoomSpring.CurrentPos - CoreZoom) > 0.5
			do
				RunService.RenderStepped:Wait()
			end

			self._SyncingZoom = false
		end

		-- Unbind camera update function from render stepped

		RunService:UnbindFromRenderStep("SUCameraUpdate")

		-- Unbind Keyboard Zoom Input function in case it was active

		RunService:UnbindFromRenderStep("SUCameraKeyboardZoom")

		-- Disable Popper

		Popper.SetEnabled(false)

		-- Perform Janitor cleanup

		self._Janitor:Cleanup()

		-- Reset CameraType

		if game.Workspace.CurrentCamera then
			game.Workspace.CurrentCamera.CameraType = Enum.CameraType.Custom
		end

		-- ReInforce camera subject (Without this the core script that manages the camera seems to break)

		if
			game.Workspace.CurrentCamera
			and LocalPlayer.Character
			and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		then
			game.Workspace.CurrentCamera.CameraSubject = LocalPlayer.Character.Humanoid
		end

		-- Reset Mouse Behavior

		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIcon = self._SavedCursor

		-- Hide controller mouse icon

		self._CustomMouseIconGUIInstances.Gui.Enabled = false

		-- Reset Camera State Variables

		self._Pitch = 0
		self._Yaw = 0
		self._GamepadPan = Vector2.new(0, 0)
		self._LastThumbstickPos = Vector2.new(0, 0)
		self._CurrentGamepadSpeed = 0
		self._LastGamepadVelocity = Vector2.new(0, 0)
		self._ZoomState = "Neutral"
		self._ZoomInKeyDown = false
		self._ZoomOutKeyDown = false
		self._YAxisCorrectionValues =
			{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
		self._XAxisCorrectionValues =
			{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
		self._ZAxisCorrectionValues =
			{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
		self._ZoomCorrectionValues =
			{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
		self._CurrentCorrectedZoom = self.StartZoom
		self._V3SpringConcluded = true
		self._LastFocusPosition = nil
		self._LastRootPartPosition = nil
		self._LastCharacterVelocity = nil
		self._ControllerZoomCycleInverted = false
		self._ActiveTouchInputs = {}
		self._LastPinchDiameter = nil

		-- Set AutoRotate to true if possible

		if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
			LocalPlayer.Character.Humanoid.AutoRotate = true
		end

		-- Reset Vector3 Spring

		self._Vector3Spring:Reset(Vector3.new())

		-- Reset CameraShake

		for i, CShakeInstance in self._CamShakeInstances do
			self._CamShakeInstances[i] = nil
		end

		-- Reset Character LocalTransparencyModifier

		local Character = self._CharacterOverriden == false and LocalPlayer.Character or self._CharacterOverride

		if Character then
			for _, Descendant in Character:GetDescendants() do
				if Descendant:IsA("BasePart") then
					Descendant.LocalTransparencyModifier = 0
				end
			end
		end
	end

	self._Enabled = Enabled -- Might cause method to be droped if code yields for to long
end

--// Camera Update //--

function PercentDiffFromA(A: number, B: number): number
	local Difference = B - A

	if Difference <= 1e-5 then
		return 0 -- no change
	end

	if A == 0 then
		return math.huge -- inf increase
	end

	return math.round((Difference / A) * 100) -- 0 < decrease / 0 > increase
end

function SUCamera._Update(self: SUCamera, DT)
	debug.profilebegin("ShiftUnlockedUpdate")

	-- process gamepad input (regardless of if '_Update' can be performed to remain consistant with other input handling)

	self:_ProccessGamepadInput(DT)

	if self._CurrentRootPart == nil or self._CurrentCamera == nil or self._CurrentHumanoid == nil then
		-- Cannot perform update operation:
		return
	end

	-- Update Mouse state and "Mouse" Icon

	if self._HidingMouseIcon == false then
		if self.MouseLocked == true then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter

			if self.LockedIcon then
				UserInputService.MouseIcon = self.LockedIcon
			else
				UserInputService.MouseIcon = self._SavedCursor
			end
		else
			UserInputService.MouseBehavior = Enum.MouseBehavior.Default

			if self.UnlockedIcon then
				UserInputService.MouseIcon = self.UnlockedIcon
			else
				UserInputService.MouseIcon = self._SavedCursor
			end
		end
	end

	-- Check integrity of custom mouse icon gui

	self:_CheckCustomMouseIconGUIIntegrity()

	-- Custom mouse icon

	if self.LockedIcon then
		self._CustomMouseIconGUIInstances.Icon.Image = self.LockedIcon
	end

	if
		self.LockedIcon
		and self.MouseLocked == true
		and UserInputService.MouseIconEnabled
		and (
			self._CurrentInputMethod == "Touch"
			or (self._CurrentInputMethod == "Gamepad" and self.AdjustedControllerIconDisplay)
		)
	then
		self._CustomMouseIconGUIInstances.Gui.Enabled = true

		UserInputService.MouseIcon = "http://www.roblox.com/asset/?id=116979418511572" -- switch icon to blank in case of controller to hide the roblox mouse icon
		self._HidingMouseIcon = true
	else
		self._CustomMouseIconGUIInstances.Gui.Enabled = false
		self._HidingMouseIcon = false
	end

	-- Update ZoomSpring properties

	self._ZoomSpring.MinValue = self.MinZoom
	self._ZoomSpring.MaxValue = self.MaxZoom

	self._ZoomSpring.Freq = self.ZoomStiffness

	-- Update Vector3Spring Damping and Frequency

	self._Vector3Spring.Spring.Damping = math.clamp(self.VelocityOffsetDamping, 0, 1)
	self._Vector3Spring.Spring.Frequency = math.clamp(self.VelocityOffsetFrequency, 1e-5, math.huge)

	-- Set Camera FOV

	self._CurrentCamera.FieldOfView = self.FOV

	-- Initialize variables used for side correction, occlusion, and calculating camera focus/rotation

	local RootPartPos = self._CurrentRootPart.CFrame.Position
	local RootPartUnrotatedCFrame = CFrame.new(RootPartPos)

	local YawRotation = CFrame.Angles(0, self._Yaw, 0)
	local PitchRotation = CFrame.Angles(self._Pitch, 0, 0)

	local RootPartCFrameWithYawRotation = RootPartUnrotatedCFrame * YawRotation

	local CameraOffset = Vector3.new(self.CameraOffset.X, self.CameraOffset.Y, self.CameraOffset.Z)

	local XOffset = CFrame.new(CameraOffset.X, 0, 0)
	local YOffset = CFrame.new(0, CameraOffset.Y, 0)
	local ZOffset = CFrame.new(0, 0, CameraOffset.Z)

	local CameraYawRotationAndXOffset = YawRotation -- First rotate around the Y axis (look left/right)
		* XOffset -- Then perform the desired offset (so camera is centered to side of player instead of directly on player)

	local CameraPitchRotationAndYOffset = PitchRotation * YOffset

	local CameraPitchYawRotationAndXYOffset = CameraYawRotationAndXOffset * CameraPitchRotationAndYOffset

	local Focus = self.FreeCamMode == false and RootPartUnrotatedCFrame * (CameraPitchYawRotationAndXYOffset * ZOffset)
		or self.FreeCamCFrame

	--// Aplly Focus changes if needed

	-- Velocity Offset

	if self._LastFocusPosition == nil or self._LastRootPartPosition == nil or self._LastCharacterVelocity == nil then
		-- First Frame:
		self._LastFocusPosition = Focus.Position
		self._LastRootPartPosition = RootPartPos
		self._LastCharacterVelocity = Vector3.new()
	end

	local FocusVelocity = Focus.Position - self._LastFocusPosition :: Vector3
	local CharacterVelocity = RootPartPos - self._LastRootPartPosition :: Vector3

	self._LastFocusPosition = Focus.Position
	self._LastRootPartPosition = RootPartPos

	local IngnoreVelocityThisFrame = false
	local PercentDiff =
		PercentDiffFromA((self._LastCharacterVelocity :: Vector3).Magnitude, CharacterVelocity.Magnitude)

	if PercentDiff > self._TeleportationThreshold * (DT / (1 / 60)) then
		-- Skip this frame if there has been a proportionally big increase of velocity since the last frame:
		-- We do this to avoid teleportation velocity spikes:
		-- This solution does skip frames that are caused by normal movement but it is good enough were there are no noticeable changes in testing:
		IngnoreVelocityThisFrame = true
	end

	if self.FreeCamMode == true then
		-- FreeCam mode is enabled we want to negate any effects of velocity offset for this frame:
		IngnoreVelocityThisFrame = true
		self._Vector3Spring:Reset(Vector3.new())
		self._V3SpringConcluded = true
	end

	if
		self.VelocityOffset == true
		and FocusVelocity.Magnitude > self.VelocityOffsetVelocityThreshold
		and CharacterVelocity.Magnitude > self.VelocityOffsetVelocityThreshold
		and (IngnoreVelocityThisFrame == false or self.AllowVelocityOffsetOnTeleport == true)
	then
		self._Vector3Spring:SetGoal(FocusVelocity * -1)
		Focus = Focus + self._Vector3Spring:Step(DT)

		self._V3SpringConcluded = false
	elseif self._V3SpringConcluded == false then
		self._Vector3Spring:SetGoal(Vector3.new())
		Focus = Focus + self._Vector3Spring:Step(DT)

		if self._Vector3Spring:GetDisplacement() <= 0.0001 then
			self._V3SpringConcluded = true
		end
	end

	self._LastCharacterVelocity = CharacterVelocity

	-- Camera Shake

	local PosAddShake = Vector3.new()
	local RotAddShake = Vector3.new()

	local CShakeInstances = self._CamShakeInstances

	for i, CShakeInstance in CShakeInstances do
		-- Determine Camera shake based on all active shakes and mark inactive ones for removal:
		local State = CShakeInstance:GetState()

		if State == CameraShakeState.Inactive and CShakeInstance.DeleteOnInactive then
			self._CamShakeInstancesToRemove[#self._CamShakeInstancesToRemove + 1] = i
		elseif State ~= CameraShakeState.Inactive then
			local Shake = CShakeInstance:_UpdateShake(DT)
			PosAddShake = PosAddShake + (Shake * CShakeInstance.PositionInfluence)
			RotAddShake = RotAddShake + (Shake * CShakeInstance.RotationInfluence)
		end
	end

	for i = #self._CamShakeInstancesToRemove, 1, -1 do
		local Index = self._CamShakeInstancesToRemove[i]
		table.remove(CShakeInstances, Index)
		self._CamShakeInstancesToRemove[i] = nil
	end

	local ShakeCFrame = CFrame.new(PosAddShake)
		* CFrame.Angles(0, math.rad(RotAddShake.Y), 0)
		* CFrame.Angles(math.rad(RotAddShake.X), 0, math.rad(RotAddShake.Z))

	Focus = Focus * ShakeCFrame

	--// Avoid useless operations if FreeCam mode is enabled

	if self.FreeCamMode == true then
		self._CurrentCFrame = Focus
		self._CurrentCamera.CFrame = self._CurrentCFrame
		self._CurrentCamera.Focus = Focus

		debug.profileend()

		return -- skip the rest of the update for this frame
	end

	--// FOCUS CORRECTIONS (Order is important)

	local LocalFocusOffsetFromRotatedRoot = RootPartCFrameWithYawRotation:ToObjectSpace(Focus)

	local Goal
	local Origin
	local VecToFocus

	-- Y axis correction

	Origin = RootPartPos
	Goal = Vector3.new(RootPartPos.X, Focus.Position.Y, RootPartPos.Z)
	VecToFocus = Goal - RootPartPos

	Focus = self:_ApplyCorrectionForAxis(Focus, Origin, Goal, VecToFocus, DT, "_YAxisCorrectionValues")

	-- X axis correction

	local FocusOnlyXOffset = (RootPartCFrameWithYawRotation * CFrame.new(LocalFocusOffsetFromRotatedRoot.X, 0, 0)).Position

	Origin = Vector3.new(RootPartPos.X, Focus.Position.Y, RootPartPos.Z)
	Goal = Vector3.new(FocusOnlyXOffset.X, Focus.Position.Y, FocusOnlyXOffset.Z)
	VecToFocus = Goal - Origin

	Focus = self:_ApplyCorrectionForAxis(Focus, Origin, Goal, VecToFocus, DT, "_XAxisCorrectionValues")

	-- Z axis correction

	local FocusZAxisOffset = (RootPartCFrameWithYawRotation * CFrame.new(0, 0, LocalFocusOffsetFromRotatedRoot.Z)).Position
		- RootPartCFrameWithYawRotation.Position

	Origin = Focus.Position - FocusZAxisOffset
	Goal = Focus.Position
	VecToFocus = Goal - Origin

	Focus = self:_ApplyCorrectionForAxis(Focus, Origin, Goal, VecToFocus, DT, "_ZAxisCorrectionValues")

	--// OCCLUSION

	local Zoom = self._ZoomSpring:Step(DT)
	local DesiredCameraCFrame = Focus * CFrame.new(0, 0, Zoom)

	-- Update ZoomState

	if
		(self._ZoomSpring.Goal == self._ZoomSpring.CurrentPos)
		or math.abs(self._ZoomSpring.Goal - self._ZoomSpring.CurrentPos) < 0.0001
	then
		self._ZoomState = "Neutral"
	elseif self._ZoomSpring.Goal > self._ZoomSpring.CurrentPos then
		self._ZoomState = "ZoomingOut"
	elseif self._ZoomSpring.Goal < self._ZoomSpring.CurrentPos then
		self._ZoomState = "ZoomingIn"
	end

	-- Get Popper Distance

	local Distance = (DesiredCameraCFrame.Position - Focus.Position).Magnitude

	local PopperResult = Popper.GetDistance(Focus, Distance) -- Max Distance from Focus

	-- Handle occlusion

	local Correction = self:_GetProperCorrection(DT, Distance - PopperResult, Distance, "_ZoomCorrectionValues")
	local CorrectionUnit = DesiredCameraCFrame.LookVector.Unit
	local CurrentCFrame = DesiredCameraCFrame + (CorrectionUnit * Correction)

	-- Set Current CFrame

	self._CurrentCFrame = CurrentCFrame

	-- Set Camera CFrame

	self._CurrentCamera.CFrame = self._CurrentCFrame

	-- Set Camera Focus

	self._CurrentCamera.Focus = Focus

	-- Update Current Corrected Zoom property

	self._CurrentCorrectedZoom = Zoom - Correction

	-- Apply Character Rotation to match Camera (if needed)

	if self:_IsHumanoidControllable() == true and self.RotateCharacter == true then
		self._CurrentHumanoid.AutoRotate = false
		self._CurrentRootPart.CFrame = YawRotation + self._CurrentRootPart.Position -- Rotate character to be upright and facing the same direction as camera
	end

	self:_HandleCharacterTrasparency()

	debug.profileend()
end

function SUCamera._GetCollisionRadius(self: SUCamera)
	if self._CurrentCamera == nil then
		return 0
	end

	local ViewportSize: Vector2 = self._CurrentCamera.ViewportSize
	local AspectRatio = ViewportSize.X / ViewportSize.Y
	local FovRads = math.rad(self.FOV)
	local ImageHeight = math.tan(FovRads) * math.abs(self._CurrentCamera.NearPlaneZ)
	local ImageWidth = ImageHeight * AspectRatio

	local CornerPos = Vector3.new(ImageWidth, ImageHeight, self._CurrentCamera.NearPlaneZ)

	return CornerPos.Magnitude
end

function SUCamera._GetProperCorrection(
	self: SUCamera,
	DT: number,
	CurrentCorrection: number,
	CurrentMagnitude: number,
	AxisTableKey: string
): number
	local LastCorrectionReturned = self[AxisTableKey].LastCorrectionReturned
	local LastMangitude = self[AxisTableKey].LastMangitude
	local LastCorrection = self[AxisTableKey].LastCorrection

	-- Update Time0Preserved

	if LastCorrection == 0 and CurrentCorrection == 0 then
		self[AxisTableKey].Time0Preserved += DT
	else
		self[AxisTableKey].Time0Preserved = 0
	end

	local Time0Preserved = self[AxisTableKey].Time0Preserved

	-- Check if last correction has to be adjusted (caused by changes in camera offset)

	if LastMangitude > CurrentMagnitude then
		local Diff = LastMangitude - CurrentMagnitude
		LastCorrectionReturned -= Diff
		LastCorrectionReturned = math.max(0, LastCorrectionReturned)
	end

	local ToReturn

	if self.CorrectionReversion == false then
		ToReturn = CurrentCorrection
	elseif
		Time0Preserved >= self.TimeUntilCorrectionReversion
		or (AxisTableKey == "_ZoomCorrectionValues" and Time0Preserved > (self.TimeUntilCorrectionReversion / 2))
	then
		-- Apply gradual reversion:
		if AxisTableKey ~= "_ZoomCorrectionValues" then
			ToReturn = math.max(0, LastCorrectionReturned - (CurrentMagnitude * DT * self.CorrectionReversionSpeed))
		else
			ToReturn =
				math.max(0, LastCorrectionReturned - (CurrentMagnitude * DT * (self.CorrectionReversionSpeed * 1.75)))
		end
	elseif CurrentCorrection > LastCorrectionReturned then
		ToReturn = CurrentCorrection
	else
		ToReturn = LastCorrectionReturned
	end

	self[AxisTableKey].LastCorrectionReturned = ToReturn
	self[AxisTableKey].LastMangitude = CurrentMagnitude
	self[AxisTableKey].LastCorrection = CurrentCorrection

	return ToReturn
end

function SUCamera._ApplyCorrectionForAxis(
	self: SUCamera,
	Focus: CFrame,
	Origin: Vector3,
	Goal: Vector3,
	VecToFocus: Vector3,
	DT: number,
	AxisTableKey: string
): CFrame
	local RaycastResult = (self.RaycastChannel :: SmartRaycast.Channel):Cast(
		Origin,
		VecToFocus + (VecToFocus.Unit * self._CollisionRadius)
	)

	local Correction

	if RaycastResult then
		local HitPosition = RaycastResult.Position + (RaycastResult.Normal * self._CollisionRadius)
		Correction = self:_GetProperCorrection(DT, (HitPosition - Goal).Magnitude, VecToFocus.Magnitude, AxisTableKey)
	else
		Correction = self:_GetProperCorrection(DT, 0, VecToFocus.Magnitude, AxisTableKey)
	end

	return Focus + (-VecToFocus.Unit * Correction)
end

local ControllableStates = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Swimming] = false,
	[Enum.HumanoidStateType.Landed] = true,
}

function SUCamera._IsHumanoidControllable(self: SUCamera)
	if not self._CurrentHumanoid then
		return false
	end

	if self._CurrentHumanoid.Parent ~= LocalPlayer.Character then
		return false
	end

	local HumanoidState = self._CurrentHumanoid:GetState()

	return ControllableStates[HumanoidState]
end

--// GC Method //--

function SUCamera.Destroy(self: SUCamera)
	local CameraLogIndex = table.find(CameraLog, self)

	if CameraLogIndex == nil then
		-- Camera has already been destroyed:
		return
	end

	-- Set Enabled State to false

	self:SetEnabled(false)

	-- Destroy Janitor

	self._Janitor:Destroy()

	-- Destroy custom mouse icon GUI instances

	for _, InstanceToDestroy in self._CustomMouseIconGUIInstances do
		(InstanceToDestroy :: Instance):Destroy()
	end

	-- Remove SUCamera from CameraLog table

	table.remove(CameraLog, CameraLogIndex)
end

--// Set current camera zoom //--

function SUCamera.SetZoom(self: SUCamera, Zoom: number)
	self._ZoomSpring.Goal = Zoom
end

--// Camera Shake  //--

function SUCamera.ShakeWithInstance(
	self: SUCamera,
	CShakeInstance: CameraShakeInstance.CameraShakeInstance,
	Sustain: boolean?
): CameraShakeInstance.CameraShakeInstance
	assert(self._Enabled, "Camera must be enabled to shake")

	self._CamShakeInstances[#self._CamShakeInstances + 1] = CShakeInstance

	if Sustain == true then
		CShakeInstance:StartFadeIn()
	end

	return CShakeInstance
end

function SUCamera.Shake(
	self: SUCamera,
	Magnitude: number,
	Roughness: number,
	Sustain: boolean?,
	FadeInTime: number?,
	FadeOutTime: number?,
	PositionInfluence: Vector3?,
	RotationInfluence: Vector3?
): CameraShakeInstance.CameraShakeInstance
	assert(self._Enabled, "Camera must be enabled to shake")

	local ShakeInstance = CameraShakeInstance.new(Magnitude, Roughness, FadeInTime, FadeOutTime)

	ShakeInstance.PositionInfluence = (
		typeof(PositionInfluence) == "Vector3" and PositionInfluence or self.CameraShakeDefaultPosInfluence
	)
	ShakeInstance.RotationInfluence = (
		typeof(RotationInfluence) == "Vector3" and RotationInfluence or self.CameraShakeDefaultRotInfluence
	)

	return self:ShakeWithInstance(ShakeInstance, Sustain)
end

function SUCamera.StopShaking(self: SUCamera, FadeOutTime: number?)
	for _, CShakeInstance in self._CamShakeInstances do
		CShakeInstance:StartFadeOut(FadeOutTime or CShakeInstance.fadeInDuration)
	end
end

--// Set Character //--

function SUCamera.SetCharacter(self: SUCamera, Character)
	assert(Character ~= nil, "[ShiftUnlocked] Cannot set character because character is nil")
	assert(
		Character:FindFirstChild("Humanoid") ~= nil,
		"[ShiftUnlocked] Cannot set character because character does not have a humanoid"
	)

	if Character == LocalPlayer.Character then
		-- Switch back to normal character handling:
		self._CharacterOverride = nil
		self._CharacterOverriden = false

		self:_OnCurrentCharacterChanged(LocalPlayer.Character)
	else
		self._CharacterOverriden = true
		self._CharacterOverride = Character

		self:_OnCurrentCharacterChanged(Character)
	end
end

--// Input Related //--

function SUCamera._ApplyInput(self: SUCamera, Yaw: number, Pitch: number) -- produces a Yaw and Pitch that can be used by the Update function
	local YInvertValue = GameSettings:GetCameraYInvertValue() -- 1 or -1 we need to change input acordingly if the camera is inverted
	local PitchLimitToRadians = math.rad(math.clamp(self.PitchLimit, 1, 89.9))

	self._Yaw = self._Yaw :: number + Yaw
	self._Pitch = math.clamp(self._Pitch :: number + Pitch * YInvertValue, -PitchLimitToRadians, PitchLimitToRadians)
end

function SUCamera._ProccessGamepadInput(self: SUCamera, DT: number) -- Produces a Yaw and Pitch from GamepadPan Vector2 to be applied via "_ApplyInput" method
	K = self.GamepadKValue
	LowerK = self.GamepadLowerKValue
	Deadzone = self.GamepadDeadzone

	local GamepadPan = GamepadLinearToCurve(self._GamepadPan)

	local MaxGamepadSpeed = 6
	local SpeedFactor = 10
	local SpeedDivisor = 0.7
	local SpeedAdjustment = 20
	local VelocityThreshold = 12

	local FinalConstant = 0
	local CurrentTime = tick()

	if GamepadPan.X == 0 and GamepadPan.Y == 0 then
		if self._LastThumbstickPos.X == 0 and self._LastThumbstickPos.Y == 0 then
			self._CurrentGamepadSpeed = 0
		end
	else
		local Elapsed = (CurrentTime - self._LastThumbstickTime) * SpeedFactor
		self._CurrentGamepadSpeed = self._CurrentGamepadSpeed + (MaxGamepadSpeed * ((Elapsed ^ 2) / SpeedDivisor))

		if self._CurrentGamepadSpeed > MaxGamepadSpeed then
			self._CurrentGamepadSpeed = MaxGamepadSpeed
		end

		local Velocity = (GamepadPan - self._LastThumbstickPos) / (CurrentTime - self._LastThumbstickTime)
		local VelocityDeltaMag = (Velocity - self._LastGamepadVelocity).Magnitude

		if VelocityDeltaMag > VelocityThreshold then
			self._CurrentGamepadSpeed = self._CurrentGamepadSpeed * (SpeedAdjustment / VelocityDeltaMag)

			if self._CurrentGamepadSpeed > MaxGamepadSpeed then
				self._CurrentGamepadSpeed = MaxGamepadSpeed
			end
		end

		FinalConstant = GameSettings.GamepadCameraSensitivity * self._CurrentGamepadSpeed * DT
		self._LastGamepadVelocity = Velocity
	end

	self._LastThumbstickPos = GamepadPan
	self._LastThumbstickTime = CurrentTime

	local YawInput = -GamepadPan.X * FinalConstant * self.GamepadSensitivityModifier.X
	local PitchInput = FinalConstant * GamepadPan.Y * self.GamepadSensitivityModifier.Y

	self:_ApplyInput(YawInput, PitchInput)
end

function SUCamera._OnInputChanged(self: SUCamera, InputObject: InputObject, GameProccessed: boolean)
	if GameProccessed == true or self.MouseLocked == false or self.FreeCamMode == true then
		return
	end

	if InputObject.UserInputType == Enum.UserInputType.MouseMovement then
		-- (InputObject.Delta is affected by the cam sensitivy roblox setting)
		local YawInput = -InputObject.Delta.X * self.MouseRadsPerPixel.X
		local PitchInput = -InputObject.Delta.Y * self.MouseRadsPerPixel.Y

		self:_ApplyInput(YawInput, PitchInput)
	elseif InputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
		self._GamepadPan = Vector2.new(InputObject.Position.X, InputObject.Position.Y)
	elseif InputObject.UserInputType == Enum.UserInputType.Touch then
		if #self._ActiveTouchInputs == 1 then
			-- Camera rotation
			local InputDelta = Vector2.new(InputObject.Delta.X, InputObject.Delta.Y)
				* -1
				* self.TouchSensitivityModifier

			self:_ApplyInput(InputDelta.X, InputDelta.Y)
		elseif #self._ActiveTouchInputs == 2 and self.ZoomLocked == false and self._SyncingZoom == false then
			-- Camera Zoom
			local PinchDiameter = (self._ActiveTouchInputs[1].Position - self._ActiveTouchInputs[2].Position).Magnitude

			if self._LastPinchDiameter then
				local ZoomDelta = ((PinchDiameter - self._LastPinchDiameter) * -1) * self.ZoomSpeedTouch

				self:_ProcessZoomDelta(ZoomDelta)
			end

			self._LastPinchDiameter = PinchDiameter
		else
			self._LastPinchDiameter = nil
		end
	end
end

function OnDynamicThumbstickFrame(Position: Vector2): boolean
	local GUIObjects = LocalPlayer.PlayerGui:GetGuiObjectsAtPosition(Position.X, Position.Y)

	for _, GUIObject in ipairs(GUIObjects) do
		if GUIObject.Name == "DynamicThumbstickFrame" then
			return true
		end
	end

	return false
end

function SUCamera._OnInputBegun(self: SUCamera, InputObject: InputObject, GameProccessed: boolean)
	if GameProccessed == true or self.MouseLocked == false or self.FreeCamMode == true then
		return
	end

	if InputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
		self._GamepadPan = Vector2.new(InputObject.Position.X, InputObject.Position.Y)
	elseif InputObject.KeyCode == self.ZoomControllerKey then
		self:_OnControllerZoomInput()
	elseif InputObject.KeyCode == self.ZoomInKeyboardKey then
		self._ZoomInKeyDown = true
	elseif InputObject.KeyCode == self.ZoomOutKeyboardKey then
		self._ZoomOutKeyDown = true
	elseif
		InputObject.UserInputType == Enum.UserInputType.Touch
		and OnDynamicThumbstickFrame(Vector2.new(InputObject.Position.X, InputObject.Position.Y)) == false
	then
		self._ActiveTouchInputs[#self._ActiveTouchInputs + 1] = InputObject
	end
end

function SUCamera._OnInputEnded(self: SUCamera, InputObject: InputObject, GameProccessed: boolean)
	if InputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
		self._GamepadPan = Vector2.new(0, 0)
	elseif InputObject.KeyCode == self.ZoomInKeyboardKey then
		self._ZoomInKeyDown = false
	elseif InputObject.KeyCode == self.ZoomOutKeyboardKey then
		self._ZoomOutKeyDown = false
	elseif InputObject.UserInputType == Enum.UserInputType.Touch then
		-- Remove this input from the active touch inputs if needed

		local Index = table.find(self._ActiveTouchInputs, InputObject)

		if Index then
			table.remove(self._ActiveTouchInputs, Index)
		end

		self._LastPinchDiameter = nil
	end
end

function SUCamera._KeyboardZoomStep(self: SUCamera)
	-- Account for the keys being set to nil while held down

	if self.ZoomInKeyboardKey == nil then
		self._ZoomInKeyDown = false
	end

	if self.ZoomOutKeyboardKey == nil then
		self._ZoomOutKeyDown = false
	end

	local ZoomInState = 0
	local ZoomOutState = 0

	if self._ZoomInKeyDown == true then
		ZoomInState = 1
	end

	if self._ZoomOutKeyDown == true then
		ZoomOutState = 1
	end

	local ZoomDelta = (ZoomOutState - ZoomInState) * self.ZoomSpeedKeyboard

	if ZoomDelta ~= 0 and self.ZoomLocked == false and self._SyncingZoom == false then
		self:_ProcessZoomDelta(ZoomDelta)
	end
end

function SUCamera._OnMouseZoomInput(self: SUCamera, Wheel: number, Pan: Vector2, Pinch: number, GameProccessed: boolean)
	if
		GameProccessed == true
		or self.ZoomLocked == true
		or self.MouseLocked == false
		or self.FreeCamMode == true
		or self._SyncingZoom == true
	then
		return
	end

	local ZoomDelta = (-Wheel + Pinch) * self.ZoomSpeedMouse

	self:_ProcessZoomDelta(ZoomDelta)
end

function SUCamera._ProcessZoomDelta(self: SUCamera, ZoomDelta: number)
	-- Aditional logic for zooming to work better with SU camera collision detection

	if ZoomDelta ~= 0 and math.abs(self._CurrentCorrectedZoom - self._ZoomSpring.CurrentPos) > 0.0001 then
		-- Player tried to Zoom while the camera is corrected:
		self._ZoomSpring.Goal = self._CurrentCorrectedZoom
		self._ZoomSpring.CurrentPos = self._CurrentCorrectedZoom
		self._ZoomSpring.CurrentVelocity = 0
	end

	-- Replicate playermodule behavior

	local CurrentZoom = self._ZoomSpring.Goal
	local NewZoom

	if ZoomDelta > 0 then
		NewZoom = CurrentZoom + ZoomDelta * (1 + CurrentZoom * self.ZoomSensitivityCurvature)
	else
		NewZoom = (CurrentZoom + ZoomDelta) / (1 - ZoomDelta * self.ZoomSensitivityCurvature)
	end

	NewZoom = math.clamp(NewZoom, self.MinZoom, self.MaxZoom)

	self._ZoomSpring.Goal = NewZoom
end

function SUCamera._OnControllerZoomInput(self: SUCamera)
	if self.ZoomLocked == true or self._SyncingZoom == true then
		return
	end

	-- Adjust the StartZoom variable for the case that an incorrect value has been passed so the logic bellow makes sense

	self.StartZoom = math.clamp(self.StartZoom, self.MinZoom, self.MaxZoom)

	if self.StartZoom == self.MaxZoom and self.StartZoom == self.MinZoom then
		-- No states to alternate between:
		return
	end

	-- Calculate zoom steps based on current min/max Zoom Distance

	local IntermidiateDivisor = 2

	local Steps = {
		self.MinZoom,
		(self.StartZoom - self.MinZoom) / IntermidiateDivisor,
		self.StartZoom,
		(self.MaxZoom - self.StartZoom) / IntermidiateDivisor,
		self.MaxZoom,
	}

	-- Adjust steps if necessary

	if self.StartZoom == self.MinZoom then
		table.remove(Steps, 1)
		table.remove(Steps, 2)
	elseif self.StartZoom - self.MinZoom < IntermidiateDivisor then
		table.remove(Steps, 2)
	end

	if self.StartZoom == self.MaxZoom then
		table.remove(Steps, 4)
		table.remove(Steps, 5)
	elseif self.MaxZoom - self.StartZoom < IntermidiateDivisor then
		table.remove(Steps, 4)
	end

	-- Change Zoom State

	local CurrentState = table.find(Steps, self._ZoomSpring.Goal)

	if CurrentState == nil then
		local SmallestDiff = math.abs(self._ZoomSpring.Goal - Steps[1])
		local ClosestState = 1

		for i = 2, #Steps do
			local Diff = math.abs(self._ZoomSpring.Goal - Steps[i])

			if Diff < SmallestDiff then
				SmallestDiff = Diff
				ClosestState = i
			end
		end

		CurrentState = ClosestState
	end

	if CurrentState == #Steps then
		self._ControllerZoomCycleInverted = true
	elseif CurrentState == 1 then
		self._ControllerZoomCycleInverted = false
	end

	local GoalState

	GoalState = self._ControllerZoomCycleInverted and Steps[CurrentState :: number - 1]
		or Steps[CurrentState :: number + 1]

	if
		math.abs(self._CurrentCorrectedZoom - self._ZoomSpring.CurrentPos) > 0.0001
		and GoalState > self._CurrentCorrectedZoom
		and CurrentState ~= 1
	then
		self._ControllerZoomCycleInverted = true

		while GoalState > self._CurrentCorrectedZoom and GoalState ~= Steps[1] do
			CurrentState = CurrentState :: number - 1
			GoalState = Steps[CurrentState :: number]
		end
	end

	self._ZoomSpring.Goal = GoalState
end

local UserInputTypes = {
	[Enum.UserInputType.MouseMovement] = "Mouse&Keyboard",
	[Enum.UserInputType.Keyboard] = "Mouse&Keyboard",
	[Enum.UserInputType.MouseButton1] = "Mouse&Keyboard",
	[Enum.UserInputType.MouseButton2] = "Mouse&Keyboard",
	[Enum.UserInputType.MouseButton3] = "Mouse&Keyboard",
	[Enum.UserInputType.MouseWheel] = "Mouse&Keyboard",
	[Enum.UserInputType.Gyro] = "Touch",
	[Enum.UserInputType.Touch] = "Touch",
	[Enum.UserInputType.Gamepad1] = "Gamepad",
	[Enum.UserInputType.Gamepad2] = "Gamepad",
	[Enum.UserInputType.Gamepad3] = "Gamepad",
	[Enum.UserInputType.Gamepad4] = "Gamepad",
	[Enum.UserInputType.Gamepad5] = "Gamepad",
	[Enum.UserInputType.Gamepad6] = "Gamepad",
	[Enum.UserInputType.Gamepad7] = "Gamepad",
	[Enum.UserInputType.Gamepad8] = "Gamepad",
}

function SUCamera._OnInputTypeChanged(self: SUCamera, UserInputType: Enum.UserInputType)
	if UserInputTypes[UserInputType] then
		self._CurrentInputMethod = UserInputTypes[UserInputType]
	end
end

function SUCamera._GetCurrentInputMethod(self: SUCamera): string
	return UserInputTypes[UserInputService:GetLastInputType()]
end

--//  Character Removed/Added //--

function SUCamera._OnCurrentCharacterChanged(self: SUCamera, Character: Instance?)
	if Character ~= nil then
		local Humanoid = Character:WaitForChild("Humanoid") :: Humanoid
		self._CurrentHumanoid = Humanoid
		self._CurrentRootPart = Humanoid.RootPart
	else
		self._CurrentHumanoid = nil
		self._CurrentRootPart = nil
	end
end

--// CurrentCamera Changed //--

function SUCamera._CurrentCameraChanged(self: SUCamera, Camera: Camera?)
	self._CurrentCamera = Camera

	if Camera ~= nil then
		Camera.CameraType = Enum.CameraType.Scriptable
		self._CollisionRadius = self:_GetCollisionRadius()

		self._Janitor:Add(
			Camera:GetPropertyChangedSignal("CameraType"):Connect(function()
				Camera.CameraType = Enum.CameraType.Scriptable
			end),
			"Disconnect",
			"CameraTypeChanged"
		)

		self._Janitor:Add(
			Camera:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				self._CollisionRadius = self:_GetCollisionRadius()
			end),
			"Disconnect",
			"ViewportSizeChanged"
		)

		self._Janitor:Add(
			Camera:GetPropertyChangedSignal("FieldOfView"):Connect(function()
				self._CollisionRadius = self:_GetCollisionRadius()
			end),
			"Disconnect",
			"FieldOfViewChanged"
		)

		self._Janitor:Add(
			Camera:GetPropertyChangedSignal("NearPlaneZ"):Connect(function()
				self._CollisionRadius = self:_GetCollisionRadius()
			end),
			"Disconnect",
			"NearPlaneZChanged"
		)
	end
end

--// Handle Character Obstructing view //--

function SUCamera._HandleCharacterTrasparency(self: SUCamera)
	local CurrentRootPart = self._CurrentRootPart :: BasePart
	local CurrentHumanoid = self._CurrentHumanoid :: Humanoid
	local Character = CurrentHumanoid.Parent :: Model

	local Distance = (self._CurrentCFrame.Position :: Vector3 - CurrentRootPart.Position).Magnitude

	if Distance <= self.ObstructionRange then
		local ModifierValue = math.max(0.5, 1.1 - (Distance / self.ObstructionRange))

		for _, Descendant in Character:GetDescendants() do
			if Descendant:IsA("BasePart") then
				Descendant.LocalTransparencyModifier = ModifierValue
			end
		end
	elseif self._LastDistanceFromRoot <= self.ObstructionRange then
		local ModifierValue = 0

		for _, Descendant in Character:GetDescendants() do
			if Descendant:IsA("BasePart") then
				Descendant.LocalTransparencyModifier = ModifierValue
			end
		end
	end

	self._LastDistanceFromRoot = Distance
end

--// Check if custom mouse icon gui is ok //--

function SUCamera._CheckCustomMouseIconGUIIntegrity(self: SUCamera)
	for _, Instance in self._CustomMouseIconGUIInstances do
		local Moved = not ((Instance :: Instance):FindFirstAncestorOfClass("PlayerGui"))

		if Moved then
			for _, InstanceToDestroy in self._CustomMouseIconGUIInstances do
				(InstanceToDestroy :: Instance):Destroy()
			end

			self._CustomMouseIconGUIInstances = CreateMouseIconGui()

			break
		end
	end
end

return SUCamera
