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
local CameraShakedefaultPosInfluence = Vector3.new(0.15, 0.15, 0.15)
local CameraShakedefaultRotInfluence = Vector3.new(1, 1, 1)

--// Gamepad thumbstick utilities //--

-- k (positive input) and LowerK (negative input) control thumbstick sensitivity; lower values for more responsive extremes, higher values for smoother, more linear control
-- Adjust these values based on your needs
-- Current setup has more precise postive value control and fast negative value control

local k = 0.5 -- A higher k value makes the curve more linear. A lower k makes it more curved and accelerating
local LowerK = 0.9 -- Same as k, but controls the lower portion of the S-curve for negative input values
local DEADZONE = 0.25 -- this specifies the range of input values near 0 that will be mapped to 0 output. This creates a "deadzone" in the middle to prevent unintentional input.

local function SCurveTransform(t: number)
	t = math.clamp(t, -1, 1)
	if t >= 0 then
		return (k * t) / (k - t + 1)
	end
	return -((LowerK * -t) / (LowerK + t + 1))
end

local function ToSCurveSpace(t: number)
	return (1 + DEADZONE) * (2 * math.abs(t) - 1) - DEADZONE
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

--[=[
	The ShiftUnlocked Camera 

	@class SUCamera
]=]

local SUCamera = {}
SUCamera.__index = SUCamera

SUCamera.GCWarn = GCWarn
SUCamera.GlobalRaycastChannelName = GlobalRaycastChannelName
SUCamera.AutoExcludeChars = AutoExcludeChars
SUCamera.CameraShakePresets = CameraShakePresets
SUCamera.CameraShakedefaultPosInfluence = CameraShakedefaultPosInfluence
SUCamera.CameraShakedefaultRotInfluence = CameraShakedefaultRotInfluence

type SUCameraProperties = {
	FOV: number,
	_Enabled: boolean,
	_Janitor: JanitorModule.Janitor,
	LockedIcon: string?,
	UnlockedIcon: string?,
	PitchLimit: number,
	_Yaw: number,
	_Pitch: number,
	MouseRadsPerPixel: Vector2,
	_GamepadPan: Vector2,
	_LastThumbstickTime: number,
	_LastThumbstickPos: Vector2,
	GamepadSensitivityModifier: Vector2,
	_CurrentGamepadSpeed: number,
	_LastGamepadVelocity: Vector2,
	CameraOffset: Vector3,
	_CurrentRootPart: BasePart?,
	_CurrentCamera: Camera?,
	RaycastChannel: SmartRaycast.Channel | nil,
	_MouseLocked: boolean,
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
	MaxZoom: number,
	MinZoom: number,
	StartZoom: number,
	ZoomLocked: boolean,
	_ZoomSpring: ConstrainedSpring.ConstrainedSpring,
	ZoomStiffness: number,
	ZoomSpeed: number,
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
	_CurrentPopperZoom: number,
	_CamShakeInstances: { CameraShakeInstance.CameraShakeInstance },
	_CamShakeInstancesToRemove: { number },
}

export type SUCamera = typeof(setmetatable({} :: SUCameraProperties, SUCamera))

local CameraLog: { SUCamera } = {}

--// Camera Conctructor //--

function SUCamera.new(): SUCamera
	local self = setmetatable({} :: SUCameraProperties, SUCamera)

	-- Configurable Parameters

	self.FOV = 70 -- Camera FOV gets automaticly clamped to 1 - 120
	self.PitchLimit = 70 -- the max degrees the camera can angle up and down
	self.LockedIcon = nil
	self.UnlockedIcon = nil
	self.MouseRadsPerPixel = Vector2.new(0.00872664619, 0.00671951752) -- dont worry to much about this setting
	self.GamepadSensitivityModifier = Vector2.new(0.85, 0.65)
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
	self.ZoomSpeed = 1
	self.ZoomSensitivityCurvature = 0.5
	self.TimeUntilCorrectionReversion = 0.8
	self.CorrectionReversionSpeed = 2.5
	self.CorrectionReversion = true

	-- Camera State Variables

	self._Enabled = false
	self._Pitch = 0
	self._Yaw = 0
	self._MouseLocked = true
	self._CurrentCFrame = CFrame.new()
	self._CollisionRadius = self:_GetCollisionRadius()
	self._ZoomState = "Neutral"

	-- Velocty Offset

	self._V3SpringConcluded = true
	self._LastFocusPosition = nil
	self._LastRootPartPosition = nil
	self._LastCharacterVelocity = nil

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
	self._CurrentPopperZoom = self.StartZoom

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

			if SmartRaycast.GetChannelObject(self.GlobalRaycastChannelName) == nil then
				-- Global channel needs to be created by the module (defualt behavior)
				SmartRaycast.CreateChannel(self.GlobalRaycastChannelName, nil, { game.Workspace }, function(Inst)
					if Inst.Transparency == 1 or Inst.CanCollide == false then
						return true
					end

					return false
				end, Enum.RaycastFilterType.Exclude)
			end

			self.RaycastChannel = SmartRaycast.GetChannelObject(self.GlobalRaycastChannelName) :: SmartRaycast.Channel
		end

		-- Set Popper's ActiveSUCamera value

		Popper.ActiveSUCamera = self :: any -- Avoid typecheck issue due it expecting a nil value

		-- Enable Popper

		Popper.SetEnabled(true)

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
					self:_OnZoomInput(Wheel, Pan, Pinch, GameProccessed)
				end
			),
			"Disconnect"
		)

		-- Connect Character Events

		self._Janitor:Add(
			LocalPlayer.CharacterAdded:Connect(function(Character: Instance?)
				self:_OnCurrentCharacterChanged(Character)
			end),
			"Disconnect"
		)

		self._Janitor:Add(
			LocalPlayer.CharacterRemoving:Connect(function()
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

		local RaycastChannel = self.RaycastChannel :: SmartRaycast.Channel -- I love typechecking

		if self.AutoExcludeChars == true and RaycastChannel.RayParams.FilterType == Enum.RaycastFilterType.Exclude then
			local function CharacterAdded(Character)
				RaycastChannel:AppendToFDI(Character)
			end

			local function PlayerAdded(Player: Player)
				self._Janitor:Add(Player.CharacterAdded:Connect(CharacterAdded), "Disconnect", tostring(Player.UserId))
			end

			local function PlayerRemoving(Player: Player)
				self._Janitor:Remove(tostring(Player.UserId))
			end

			for _, Player in Players:GetPlayers() do
				PlayerAdded(Player)
				if
					Player.Character
					and table.find(RaycastChannel.RayParams.FilterDescendantsInstances, Player.Character) == nil
				then -- meh i don't like duping items but maybe this check is not really needed here
					RaycastChannel:AppendToFDI(Player.Character)
				end
			end

			self._Janitor:Add(Players.PlayerAdded:Connect(PlayerAdded), "Disconnect")
			self._Janitor:Add(Players.PlayerRemoving:Connect(PlayerRemoving), "Disconnect")
		end

		-- Run '_CurrentCameraChanged' and '_OnCurrentCharacterChanged'

		self:_OnCurrentCharacterChanged(LocalPlayer.Character)
		self:_CurrentCameraChanged(workspace.CurrentCamera)

		-- Make transition to custom camera smooth by facing in same direction as previous camera

		local CameraLook = (self._CurrentCamera :: Camera).CFrame.LookVector

		self._Yaw = math.atan2(-CameraLook.X, -CameraLook.Z)
		self._Pitch = math.asin(CameraLook.Y)

		-- Init/Reset Zoom Spring

		self._ZoomSpring.CurrentVelocity = 0
		self._ZoomSpring.CurrentPos = self.StartZoom
		self._ZoomSpring.Goal = self.StartZoom
	else
		-- Unbind camera update function from render stepped

		RunService:UnbindFromRenderStep("SUCameraUpdate")

		-- Disable Popper

		Popper.SetEnabled(false)

		-- Perform Janitor cleanup

		self._Janitor:Cleanup()

		-- Reset CameraType

		if self._CurrentCamera then
			self._CurrentCamera.CameraType = Enum.CameraType.Custom
		end

		-- Reset Mouse Behavior

		UserInputService.MouseBehavior = Enum.MouseBehavior.Default

		-- Reset Camera State Variables

		self._Pitch = 0
		self._Yaw = 0
		self._GamepadPan = Vector2.new(0, 0)
		self._LastThumbstickPos = Vector2.new(0, 0)
		self._CurrentGamepadSpeed = 0
		self._LastGamepadVelocity = Vector2.new(0, 0)
		self._ZoomState = "Neutral"
		self._YAxisCorrectionValues =
			{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
		self._XAxisCorrectionValues =
			{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
		self._ZAxisCorrectionValues =
			{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
		self._ZoomCorrectionValues =
			{ LastCorrectionReturned = 0, LastMangitude = 0, Time0Preserved = 0, LastCorrection = 0 }
		self._CurrentPopperZoom = self.StartZoom
		self._V3SpringConcluded = true
		self._LastFocusPosition = nil
		self._LastRootPartPosition = nil
		self._LastCharacterVelocity = nil

		-- Set AutoRotate to true if possible

		if self._CurrentHumanoid then
			self._CurrentHumanoid.AutoRotate = true
		end

		-- Reset Vector3 Spring

		self._Vector3Spring:Reset(Vector3.new(0, 0, 0))

		-- Reset CameraShake

		for i, CShakeInstance in self._CamShakeInstances do
			CShakeInstance:StartFadeOut(0)
			self._CamShakeInstances[i] = nil
		end
	end

	self._Enabled = Enabled -- Might cause method to be droped if code yields for to long
end

--// Camera Update //--

function SUCamera._Update(self: SUCamera, DT)
	debug.profilebegin("ShiftUnlockedUpdate")

	-- process gamepad input (regardless of if '_Update' can be performed to remain consistant with other input handling)

	self:_ProccessGamepadInput(DT)

	if self._CurrentRootPart == nil or self._CurrentCamera == nil or self._CurrentHumanoid == nil then
		-- Cannot perform update operation:
		return
	end

	-- Lock/Unlock Mouse (ADD ICON STUFF)

	if self._MouseLocked == true then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	-- Update ZoomSpring Limits

	self._ZoomSpring.MinValue = self.MinZoom
	self._ZoomSpring.MaxValue = self.MaxZoom

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

	local Focus = RootPartUnrotatedCFrame * (CameraPitchYawRotationAndXYOffset * ZOffset)

	--// Aplly Focus changes if needed

	-- Velocity Offset

	if self._LastFocusPosition == nil or self._LastRootPartPosition == nil then
		-- First Frame:
		self._LastFocusPosition = Focus.Position
		self._LastRootPartPosition = RootPartPos
	end

	local FocusVelocity = Focus.Position - self._LastFocusPosition :: Vector3
	local CharacterVelocity = RootPartPos - self._LastRootPartPosition :: Vector3

	self._LastFocusPosition = Focus.Position
	self._LastRootPartPosition = RootPartPos

	if
		self.VelocityOffset == true
		and FocusVelocity.Magnitude > self.VelocityOffsetVelocityThreshold
		and CharacterVelocity.Magnitude > self.VelocityOffsetVelocityThreshold
		and (
			(
				self._LastCharacterVelocity
				and self._LastCharacterVelocity.Magnitude > self.VelocityOffsetVelocityThreshold
			) or self.AllowVelocityOffsetOnTeleport == true
		)
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
			local Shake = CShakeInstance:UpdateShake(DT)
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

	local Zoom = self.ZoomLocked and 0 or self._ZoomSpring:Step(DT)
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

	-- Update Current Popper Zoom property

	self._CurrentPopperZoom = PopperResult

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
	local RaycastResult = workspace:Raycast(
		Origin,
		VecToFocus + (VecToFocus.Unit * self._CollisionRadius),
		(self.RaycastChannel :: SmartRaycast.Channel).RayParams
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

	-- Remove SUCamera from CameraLog table

	table.remove(CameraLog, CameraLogIndex)
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
		CShakeInstance:StartFadeIn(CShakeInstance.fadeInDuration)
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
		typeof(PositionInfluence) == "Vector3" and PositionInfluence or self.CameraShakedefaultPosInfluence
	)
	ShakeInstance.RotationInfluence = (
		typeof(PositionInfluence) == "Vector3" and PositionInfluence or self.CameraShakedefaultRotInfluence
	)

	return self:ShakeWithInstance(ShakeInstance, Sustain)
end

function SUCamera.StopShaking(self: SUCamera, FadeOutTime: number?)
	for _, CShakeInstance in self._CamShakeInstances do
		if CShakeInstance.fadeOutDuration == 0 then
			CShakeInstance:StartFadeOut(FadeOutTime or CShakeInstance.fadeInDuration)
		end
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
	local PitchInput = FinalConstant
		* GamepadPan.Y
		* GameSettings:GetCameraYInvertValue()
		* self.GamepadSensitivityModifier.Y

	self:_ApplyInput(YawInput, PitchInput)
end

function SUCamera._OnInputChanged(self: SUCamera, InputObject: InputObject, GameProccessed: boolean)
	if GameProccessed == true then
		return
	end

	if InputObject.UserInputType == Enum.UserInputType.MouseMovement then
		-- (InputObject.Delta is affected by the cam sensitivy roblox setting)
		local YawInput = -InputObject.Delta.X * self.MouseRadsPerPixel.X
		local PitchInput = -InputObject.Delta.Y * self.MouseRadsPerPixel.Y

		self:_ApplyInput(YawInput, PitchInput)
	elseif InputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
		self._GamepadPan = Vector2.new(InputObject.Position.X, InputObject.Position.Y)
	end
end

function SUCamera._OnInputBegun(self: SUCamera, InputObject: InputObject, GameProccessed: boolean)
	if GameProccessed == true then
		return
	end

	if InputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
		self._GamepadPan = Vector2.new(InputObject.Position.X, InputObject.Position.Y)
	end
end

function SUCamera._OnInputEnded(self: SUCamera, InputObject: InputObject, GameProccessed: boolean)
	if GameProccessed == true then
		return
	end

	if InputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
		self._GamepadPan = Vector2.new(0, 0)
	end
end

function SUCamera._OnZoomInput(self: SUCamera, Wheel: number, Pan: Vector2, Pinch: number, GameProccessed: boolean)
	if GameProccessed == true or self.ZoomLocked == true then
		return
	end

	--// Replicate playermodule behavior

	local ZoomDelta = (-Wheel + Pinch) * self.ZoomSpeed

	-- Aditional logic for zooming to work better with SU camera collision detection

	if ZoomDelta < 0 and math.abs(self._CurrentPopperZoom - self._ZoomSpring.CurrentPos) > 0.0001 then
		-- Player tried to Zoom in while the camera is "popped in":
		self._ZoomSpring.Goal = self._CurrentPopperZoom
		self._ZoomSpring.CurrentPos = self._CurrentPopperZoom
		self._ZoomSpring.CurrentVelocity = 0
	elseif ZoomDelta > 0 and math.abs(self._CurrentPopperZoom - self._ZoomSpring.CurrentPos) > 0.0001 then
		-- Player tried to Zoom out while the camera is "popped in":
		self._ZoomSpring.Goal = self._CurrentPopperZoom
		self._ZoomSpring.CurrentPos = self._CurrentPopperZoom
		self._ZoomSpring.CurrentVelocity = 0
	end

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

--//  Character Removed/Added //--

function SUCamera._OnCurrentCharacterChanged(self: SUCamera, Character: Instance?)
	if Character ~= nil then
		local Humanoid = Character:WaitForChild("Humanoid") :: Humanoid
		self._CurrentHumanoid = Humanoid :: Humanoid? -- typechecking issues...
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

return SUCamera
