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
  -- Based on ShoulderCam by RefrenceGames and Roblox Source -- 
]]

--// Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

--// Modules
local JanitorModule = require(script.Parent.janitor)
local SmartRaycast = require(script.Parent.smartraycast)
local Popper = require(script.ForkedPopper)

--// Variables
local LocalPlayer = Players.LocalPlayer
local GameSettings = UserSettings().GameSettings -- Updates RealTime
local InternalChannelName = HttpService:GenerateGUID() -- This is done so we don't collide with any other user channels

--// Settings Defualt Values
local GCWarn = true
local GlobalRaycastChannelName = InternalChannelName
local AutoExcludeChars = true

--// Gamepad thumbstick utilities //--

local k = 0.5 -- A higher k value makes the curve more linear. A lower k makes it more curved and accelerating
local LowerK = 0.9 -- Same as k, but controls the lower portion of the S-curve for negative input values
local DEADZONE = 0.25 -- his specifies the range of input values near 0 that will be mapped to 0 output. This creates a "deadzone" in the middle to prevent unintentional input.

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

--// Transform Extrapolator //--

local IdentityCFrame = CFrame.new()

local function CFrameToAxis(CFrame: CFrame): Vector3
	local Axis: Vector3, Angle: number = CFrame:ToAxisAngle()
	return Axis * Angle
end

local function AxisToCFrame(Axis: Vector3): CFrame
	local Angle: number = Axis.Magnitude

	if Angle > 1e-5 then
		return CFrame.fromAxisAngle(Axis, Angle)
	end

	return IdentityCFrame
end

local function ExtractRotation(CF: CFrame): CFrame
	local _, _, _, xx, yx, zx, xy, yy, zy, xz, yz, zz = CF:GetComponents()
	return CFrame.new(0, 0, 0, xx, yx, zx, xy, yy, zy, xz, yz, zz)
end

local TransformExtrapolator = {}
TransformExtrapolator.__index = TransformExtrapolator

type TransformExtrapolatorProperties = {
	LastFrame: CFrame?,
}

type TransformExtrapolator = typeof(setmetatable({} :: TransformExtrapolatorProperties, TransformExtrapolator))

function TransformExtrapolator.new(): TransformExtrapolator
	return setmetatable({
		LastCFrame = nil,
	} :: TransformExtrapolatorProperties, TransformExtrapolator)
end

function TransformExtrapolator:Step(
	DT: number,
	CurrentCFrame: CFrame
): { Extrapolate: (number) -> CFrame, PosVelocity: Vector3, RotVelocity: Vector3 }
	local LastCFrame = self.lastCFrame or CurrentCFrame
	self.LastCFrame = CurrentCFrame

	local CurrentPos = CurrentCFrame.Position
	local CurrentRot = ExtractRotation(CurrentCFrame)

	local LastPos = LastCFrame.Position
	local LastRot = ExtractRotation(LastCFrame)

	-- Estimate velocities from the delta between now and the last frame
	-- This estimation can be a little noisy.
	local DP = (CurrentPos - LastPos) / DT
	local DR = CFrameToAxis(CurrentRot * LastRot:Inverse()) / DT

	local function Extrapolate(t) -- get CFrame in the future t time?
		local P = DP * t + CurrentPos
		local R = AxisToCFrame(DR * t) * CurrentRot
		return R + P
	end

	return {
		Extrapolate = Extrapolate,
		PosVelocity = DP,
		RotVelocity = DR,
	}
end

function TransformExtrapolator:Reset()
	self.LastCFrame = nil
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

type SUCameraProperties = {
	FOV: number,
	_Enabled: boolean,
	_Janitor: any, -- Typechecking bug? Janitor type does not export properly
	LockedIcon: string?,
	UnlockedIcon: string?,
	PitchLimit: number,
	_Yaw: number,
	_Pitch: number,
	MouseRadsPerPixel: Vector2,
	_GamepadPan: Vector2,
	_LastThumbstickTime: number?,
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
	_TransformExtrapolator: TransformExtrapolator,
	RotateCharacter: boolean,
	_CameraOffset: Vector3,
	PopOutSpeed: number,
	_LastSideCorrectionMagnitude: number,
}

export type SUCamera = typeof(setmetatable({} :: SUCameraProperties, SUCamera))

local CameraLog: { SUCamera } = {}

--// Camera Conctructor //--

function SUCamera.new(): SUCamera
	local self = setmetatable({} :: SUCameraProperties, SUCamera)

	-- Configurable Parameters

	self.FOV = 70 -- Camera FOV gets automaticly clamped to 1 - 120
	self.PitchLimit = 45 -- the max degrees the camera can angle up and down
	self.LockedIcon = nil
	self.UnlockedIcon = nil
	self.MouseRadsPerPixel = Vector2.new(0.00872664619, 0.00671951752) -- dont worry to much about this setting
	self.GamepadSensitivityModifier = Vector2.new(0.85, 0.65)
	self.CameraOffset = Vector3.new(1.75, 1.5, 10) -- Z Axis will be ingnored (legay value 1.75,1.5)
	self.RaycastChannel = nil
	self.ObstructionRange = 6.5 -- Distance from the camera required to start making the local character transparent
	self.PopOutSpeed = 10 -- sec
	self.RotateCharacter = true

	-- State Variables

	self._Enabled = false
	self._Pitch = 0
	self._Yaw = 0
	self._MouseLocked = true
	self._CurrentCFrame = CFrame.new()
	self._CollisionRadius = self:_GetCollisionRadius()
	self._CameraOffset = self.CameraOffset

	-- Occlusion

	self._LastDistanceFromRoot = 0
	self._LastSideCorrectionMagnitude = math.abs(self.CameraOffset.X)

	-- Gamepad Variables

	self._GamepadPan = Vector2.new(0, 0)
	self._LastThumbstickTime = nil
	self._LastThumbstickPos = Vector2.new(0, 0)
	self._CurrentGamepadSpeed = 0
	self._LastGamepadVelocity = Vector2.new(0, 0)

	-- DataModel refrences

	self._Janitor = JanitorModule.new()
	self._TransformExtrapolator = TransformExtrapolator.new()
	self._CurrentRootPart = nil
	self._CurrentHumanoid = nil
	self._CurrentCamera = nil

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

function SUCamera:SetEnabled(Enabled: boolean)
	if Enabled == self._Enabled then
		-- No need to perform any action:
		return
	end

	if self._Enabled == false then
		-- Make sure that other cameras are not enabled

		if #CameraLog > 1 then
			for _, Cam in pairs(CameraLog) do
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

		-- Set Occlusion Vars that need to be up to date with current data

		self._LastSideCorrectionMagnitude = math.abs(self.CameraOffset.X)

		-- Set Popper's ActiveSUCamera value

		Popper.ActiveSUCamera = self

		-- Enable Popper

		Popper:SetEnabled(true)

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

		if
			self.AutoExcludeChars == true
			and self.RaycastChannel.RayParams.FilterType == Enum.RaycastFilterType.Exclude
		then
			local function CharacterAdded(Character)
				self.RaycastChannel:AppendToFDI(Character)
			end

			local function PlayerAdded(Player: Player)
				self._Janitor:Add(Player.CharacterAdded:Connect(CharacterAdded), "Disconnect", tostring(Player.UserId)) -- d
			end

			local function PlayerRemoving(Player: Player)
				self._Janitor:Remove(tostring(Player.UserId))
			end

			for _, Player in Players:GetPlayers() do
				PlayerAdded(Player)
			end

			self._Janitor:Add(Players.PlayerAdded:Connect(PlayerAdded), "Disconnect")
			self._Janitor:Add(Players.PlayerRemoving:Connect(PlayerRemoving), "Disconnect")
		end

		-- Run '_CurrentCameraChanged' and '_OnCurrentCharacterChanged'

		self:_OnCurrentCharacterChanged(LocalPlayer.Character)
		self:_CurrentCameraChanged(workspace.CurrentCamera)
	else
		-- Unbind camera update function from render stepped

		RunService:UnbindFromRenderStep("SUCameraUpdate")

		-- Disable Popper

		Popper:SetEnabled(false)

		-- Perform Janitor cleanup

		self._Janitor:cleanup()

		-- Reset CameraType

		if self._CurrentCamera then
			self._CurrentCamera.CameraType = Enum.CameraType.Custom
		end

		-- Reset Camera State Variables

		self._Pitch = 0
		self._Yaw = 0
		self._GamepadPan = Vector2.new(0, 0)
		self._LastThumbstickTime = nil
		self._LastThumbstickPos = Vector2.new(0, 0)
		self._CurrentGamepadSpeed = 0
		self._LastGamepadVelocity = Vector2.new(0, 0)
	end
end

--// Camera Update //--

function SUCamera:_Update(DT)
	debug.profilebegin("ShiftUnlockedUpdate")

	-- process gamepad input (regardless of if '_Update' can be performed to remain consistant with other input handling)

	self:_ProccessGamepadInput(DT)

	if self._CurrentRootPart == nil or self._CurrentCamera == nil then
		return
	end

	-- Lock/Unlock Mouse (ADD ICON STUFF)

	if self._MouseLocked == true then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	-- Set Camera FOV

	self._CurrentCamera.FieldOfView = self.FOV

	-- Calculate Actual Camera Offset

	self._CameraOffset = self.CameraOffset

	-- Initialize variables used for side correction, occlusion, and calculating camera focus/rotation

	local CollisionRadius = self._CollisionRadius
	local CorrectionReversionModifierX = (math.abs(self._CameraOffset.X) / self.PopOutSpeed) * DT
	local CorrectionReversionModifierAll = (self._CameraOffset.Magnitude / self.PopOutSpeed) * DT

	local RootPartPos = self._CurrentRootPart.CFrame.Position
	local RootPartUnrotatedCFrame = CFrame.new(RootPartPos)

	local YawRotation = CFrame.Angles(0, self._Yaw, 0)
	local PitchRotation = CFrame.Angles(self._Pitch, 0, 0)

	local XOffset = CFrame.new(self._CameraOffset.X, 0, 0)
	local YOffset = CFrame.new(0, self._CameraOffset.Y, 0)
	local ZOffset = CFrame.new(0, 0, self._CameraOffset.Z)

	local CameraYawRotationAndXOffset = YawRotation -- First rotate around the Y axis (look left/right)
		* XOffset -- Then perform the desired offset (so camera is centered to side of player instead of directly on player)

	self._CurrentCFrame = RootPartUnrotatedCFrame * CameraYawRotationAndXOffset

	--// Handle/Calculate side correction when player is adjacent to a wall (so camera doesn't go in the wall)

	local VecToFocus = self._CurrentCFrame.Position - RootPartPos
	local RaycastResult =
		workspace:Raycast(RootPartPos, VecToFocus + (VecToFocus.Unit * CollisionRadius), self.RaycastChannel.RayParams)

	if RaycastResult then
		local HitPosition = RaycastResult.Position + (RaycastResult.Normal * CollisionRadius)
		local Correction = HitPosition - self._CurrentCFrame.Position

		-- Update cameraFocus to reflect side correction

		CameraYawRotationAndXOffset = CameraYawRotationAndXOffset + (-VecToFocus.Unit * Correction.Magnitude)
	end

	self._LastSideCorrectionMagnitude = CameraYawRotationAndXOffset.Position.Magnitude

	-- Calculate CFrame for camera with x correction

	local CameraCFrameInSubjectSpace = CameraYawRotationAndXOffset
		* PitchRotation -- rotate around the X axis (look up/down)
		* YOffset -- move camera up/vertically
		* ZOffset -- move camera back

	self._CurrentCFrame = RootPartUnrotatedCFrame * CameraCFrameInSubjectSpace

	--// OCCLUSION

	local Focus = RootPartUnrotatedCFrame * CameraYawRotationAndXOffset * PitchRotation * YOffset

	local RotatedFocus = CFrame.new(Focus.Position, self._CurrentCFrame.Position)
		* CFrame.new(0, 0, 0, -1, 0, 0, 0, 1, 0, 0, 0, -1)

	-- Get extrapolation result

	local ExtrapolationResult = self._TransformExtrapolator:Step(DT, RotatedFocus)

	-- Get Popper Distance

	local Distance = (self._CurrentCFrame.Position - Focus.Position).Magnitude

	local PopperResult = Popper.GetDistance(RotatedFocus, Distance, ExtrapolationResult)

	-- Handle occlusion

	local Correction = Distance - PopperResult
	local CorrectionUnit = self._CurrentCFrame.LookVector.Unit
	self._CurrentCFrame = self._CurrentCFrame + (CorrectionUnit * Correction)

	-- Set Camera CFrame

	self._CurrentCamera.CFrame = self._CurrentCFrame

	-- Set Camera Focus

	self._CurrentCamera.Focus = RootPartUnrotatedCFrame
		* (CameraCFrameInSubjectSpace * CFrame.new(0, 0, CameraCFrameInSubjectSpace:Inverse().Position.Z))

	-- Apply Character Rotation to match Camera (if needed)

	if self:_IsHumanoidControllable() == true and self.RotateCharacter == true then
		self._CurrentHumanoid.AutoRotate = false
		self._CurrentRootPart.CFrame = CFrame.Angles(0, self._Yaw, 0) + self._CurrentRootPart.Position :: Vector3 -- Rotate character to be upright and facing the same direction as camera
	end

	self:_HandleCharacterTrasparency()

	debug.profileend()
end

function SUCamera:_GetCollisionRadius()
	if self._CurrentCamera == nil then
		return 0
	end

	local ViewportSize: Vector2 = self._CurrentCamera.ViewportSize
	local AspectRatio = ViewportSize.X / ViewportSize.Y
	local FovRads = math.rad(self.FOV)
	local ImageHeight = math.tan(FovRads) * math.abs(self._CurrentCamera.NearPlaneZ)
	local ImageWidth = ImageHeight * AspectRatio

	local CornerPos = Vector3.new(ImageWidth, ImageHeight, self._CurrentCamera.NearPlaneZ)

	return CornerPos.Magnitude --/ 3
end

local ControllableStates = {
	[Enum.HumanoidStateType.Running] = true,
	[Enum.HumanoidStateType.RunningNoPhysics] = true,
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.Swimming] = false,
	[Enum.HumanoidStateType.Landed] = true,
}

function SUCamera:_IsHumanoidControllable()
	if not self._CurrentHumanoid then
		return false
	end

	local HumanoidState = self._CurrentHumanoid:GetState()

	return ControllableStates[HumanoidState]
end

--// GC Method //--

function SUCamera:Destroy()
	local CameraLogIndex = table.find(CameraLog, self)

	if CameraLogIndex == nil then
		-- Camera has already been destroyed:
		return
	end

	-- Unbind camera update function from render stepped

	RunService:UnbindFromRenderStep("SUCameraUpdate")

	-- Destroy Janitor

	self._Janitor:Destroy()

	-- Remove SUCamera from CameraLog table

	table.remove(CameraLog, CameraLogIndex)
end

--// Input Related //--

function SUCamera:_ApplyInput(Yaw: number, Pitch: number) -- produces a Yaw and Pitch that can be used by the Update function
	local YInvertValue = GameSettings:GetCameraYInvertValue()
	local PitchLimitToRadians = math.rad(math.clamp(self.PitchLimit, 1, 360))

	self._Yaw = self._Yaw :: number + Yaw
	self._Pitch = math.clamp(self._Pitch :: number + Pitch * YInvertValue, -PitchLimitToRadians, PitchLimitToRadians)
end

function SUCamera:_ProccessGamepadInput(DT: number) -- Produces a Yaw and Pitch from GamepadPan Vector2 to be applied via "_ApplyInput" method
	local GamepadPan = GamepadLinearToCurve(self._GamepadPan)
	local FinalConstant = 0
	local CurrentTime = tick()

	if GamepadPan.X == 0 and GamepadPan.Y == 0 then
		if self._LastThumbstickPos.X == 0 and self._LastThumbstickPos.Y == 0 then
			self._CurrentGamepadSpeed = 0
		end
	else
		local Elapsed = (CurrentTime - self._LastThumbstickTime) * 10
		self._CurrentGamepadSpeed = self._CurrentGamepadSpeed + (6 * ((Elapsed ^ 2) / 0.7))

		if self._CurrentGamepadSpeed > 6 then
			self._CurrentGamepadSpeed = 6
		end

		local Velocity = (GamepadPan - self._LastThumbstickPos) / (CurrentTime - self._LastThumbstickTime)
		local VelocityDeltaMag = (Velocity - self._LastGamepadVelocity).Magnitude

		if VelocityDeltaMag > 12 then
			self._CurrentGamepadSpeed = self._CurrentGamepadSpeed * (20 / VelocityDeltaMag)

			if self._CurrentGamepadSpeed > 6 then
				self._CurrentGamepadSpeed = 6
			end
		end

		FinalConstant = GameSettings.GamepadCameraSensitivity * self._CurrentGamepadSpeed * DT
		self._LastGamepadVelocity = (GamepadPan - self._LastThumbstickPos) / (CurrentTime - self._LastThumbstickTime)
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

function SUCamera:_OnInputChanged(InputObject: InputObject, GameProccessed: boolean)
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

function SUCamera:_OnInputBegun(InputObject: InputObject, GameProccessed: boolean)
	if GameProccessed == true then
		return
	end

	if InputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
		self._GamepadPan = Vector2.new(InputObject.Position.X, InputObject.Position.Y)
	end
end

function SUCamera:_OnInputEnded(InputObject: InputObject, GameProccessed: boolean)
	if GameProccessed == true then
		return
	end

	if InputObject.KeyCode == Enum.KeyCode.Thumbstick2 then
		self._GamepadPan = Vector2.new(0, 0)
	end
end

--//  Character Removed/Added //--

function SUCamera:_OnCurrentCharacterChanged(Character: Instance?)
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

function SUCamera:_CurrentCameraChanged(Camera: Camera?)
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

function SUCamera:_HandleCharacterTrasparency()
	local Distance = (self._CurrentCFrame.Position :: Vector3 - self._CurrentRootPart.Position).Magnitude

	if Distance <= self.ObstructionRange then
		local ModifierValue = math.max(0.5, 1.1 - (Distance / self.ObstructionRange))

		for _, Descendant in pairs(self._CurrentHumanoid.Parent:GetDescendants()) do
			if Descendant:IsA("MeshPart") or Descendant:IsA("Part") then
				Descendant.LocalTransparencyModifier = ModifierValue
			end
		end
	elseif self._LastDistanceFromRoot <= self.ObstructionRange then
		local ModifierValue = 0

		for _, Descendant in pairs(self._CurrentHumanoid.Parent:GetDescendants()) do
			if Descendant:IsA("MeshPart") or Descendant:IsA("Part") then
				Descendant.LocalTransparencyModifier = ModifierValue
			end
		end
	end

	self._LastDistanceFromRoot = Distance
end

return SUCamera
