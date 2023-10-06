--!strict

--[[
 _____ _     _  __ _   _   _       _            _            _ 
/  ___| |   (_)/ _| | | | | |     | |          | |          | |
\ `--.| |__  _| |_| |_| | | |_ __ | | ___   ___| | _____  __| |
 `--. \ '_ \| |  _| __| | | | '_ \| |/ _ \ / __| |/ / _ \/ _` |
/\__/ / | | | | | | |_| |_| | | | | | (_) | (__|   <  __/ (_| |
\____/|_| |_|_|_|  \__|\___/|_| |_|_|\___/ \___|_|\_\___|\__,_|
                                                                                                                                  
       -- A Third-Person Camera for the Roblox Engine -- 
 -- Give credit to Yiannis123 if you use this in your project -- 
          -- Based on ShoulderCam by RefrenceGames -- 
]]

--// Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

--// Modules
local JanitorModule = require(script.Parent.janitor)
local SmartRaycast = require(script.Parent.smartraycast)

--// Variables
local LocalPlayer = Players.LocalPlayer
local GameSettings = UserSettings().GameSettings -- Updates RealTime
local InternalChannelName = HttpService:GenerateGUID() -- This is done so we don't collide with any other user channels

--// Settings Defualt Values

local GCWarn = true
local GlobalRaycastChannelName = InternalChannelName

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

--// ShiftUnlocked Camera //--

--[=[
	The ShiftUnlocked Camera 

	@class SUCamera
]=]

local SUCamera = {}
SUCamera.__index = SUCamera

SUCamera.GCWarn = GCWarn
SUCamera.GlobalRaycastChannelName = GlobalRaycastChannelName

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
	_CurrentHumanoid: Humanoid?,
	_CurrentCFrame: CFrame,
	ObstructionRange: number,
	_LastDistanceFromRoot: number,
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
	self.MouseRadsPerPixel = Vector2.new(0.00872664619, 0.00671951752) -- make this reflect cam sensitivity setting?
	self.GamepadSensitivityModifier = Vector2.new(0.85, 0.65)
	self.CameraOffset = Vector3.new(1.7, 1.5, 10) -- Legacy Default Value Vector3.new(1.75, 0, 0)
	self.RaycastChannel = nil
	self.ObstructionRange = 6.5

	-- State Variables

	self._Enabled = false
	self._Pitch = 0
	self._Yaw = 0
	self._MouseLocked = true
	self._CurrentCFrame = CFrame.new()
	self._LastDistanceFromRoot = 0

	-- Gamepad Variables

	self._GamepadPan = Vector2.new(0, 0)
	self._LastThumbstickTime = nil
	self._LastThumbstickPos = Vector2.new(0, 0)
	self._CurrentGamepadSpeed = 0
	self._LastGamepadVelocity = Vector2.new(0, 0)

	-- DataModel refrences

	self._Janitor = JanitorModule.new()
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
				end, Enum.RaycastFilterType.Exclude)
			end

			self.RaycastChannel = SmartRaycast.GetChannelObject(self.GlobalRaycastChannelName)
		end

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

		-- Run '_CurrentCameraChanged' and '_OnCurrentCharacterChanged'

		self:_OnCurrentCharacterChanged(LocalPlayer.Character)
		self:_CurrentCameraChanged(workspace.CurrentCamera)
	else
		-- Unbind camera update function from render stepped

		RunService:UnbindFromRenderStep("SUCameraUpdate")

		-- Perform Janitor cleanup

		self._Janitor:cleanup()

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
	-- process gamepad input (regardless of if '_Update' can be performed to remain consistant with other input handling)

	self:_ProccessGamepadInput(DT)

	if self._CurrentRootPart == nil then
		return
	end

	-- Lock/Unlock Mouse (ADD ICON STUFF)

	if self._MouseLocked == true then
		UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	-- Initialize variables used for side correction, occlusion, and calculating camera focus/rotation

	local CollisionRadius = self:_GetCollisionRadius() -- We run this every time since Viewport Size is not constant

	local RootPartPos = self._CurrentRootPart.CFrame.Position
	local RootPartUnrotatedCFrame = CFrame.new(RootPartPos)

	local YawRotation = CFrame.Angles(0, self._Yaw, 0)
	local PitchRotation = CFrame.Angles(self._Pitch, 0, 0)

	local XOffset = CFrame.new(self.CameraOffset.X, 0, 0)
	local YOffset = CFrame.new(0, self.CameraOffset.Y, 0)
	local ZOffset = CFrame.new(0, 0, self.CameraOffset.Z)

	local CameraYawRotationAndXOffset = YawRotation -- First rotate around the Y axis (look left/right)
		* XOffset -- Then perform the desired offset (so camera is centered to side of player instead of directly on player)

	local CameraFocus = RootPartUnrotatedCFrame * CameraYawRotationAndXOffset

	-- Handle/Calculate side correction when player is adjacent to a wall (so camera doesn't go in the wall)

	local VecToFocus = CameraFocus.Position - RootPartPos
	local RaycastResult =
		workspace:Raycast(RootPartPos, VecToFocus + (VecToFocus.Unit * CollisionRadius), self.RaycastChannel.RayParams)

	if RaycastResult then
		local HitPosition = RaycastResult.Position + (RaycastResult.Normal * CollisionRadius)
		local Correction = HitPosition - CameraFocus.Position

		-- Update cameraFocus to reflect side correction

		CameraYawRotationAndXOffset = CameraYawRotationAndXOffset + (-VecToFocus.Unit * Correction.Magnitude)
		CameraFocus = RootPartUnrotatedCFrame * CameraYawRotationAndXOffset
	end

	-- TEST FOCUS HERE AND AFTER HERE --

	self._CurrentCamera.Focus = CameraFocus -- PROB DONE HERE DUE TO DEPRECATED CALL

	-- Calculate CFrame for camera with x correction

	local CameraCFrameInSubjectSpace = CameraYawRotationAndXOffset
		* PitchRotation -- rotate around the X axis (look up/down)
		* YOffset -- move camera up/vertically
		* ZOffset -- move camera back

	self._CurrentCFrame = RootPartUnrotatedCFrame * CameraCFrameInSubjectSpace

	-- Handle occlusion

	VecToFocus = self._CurrentCFrame.Position - RootPartPos
	RaycastResult =
		workspace:Raycast(RootPartPos, VecToFocus + (VecToFocus.Unit * CollisionRadius), self.RaycastChannel.RayParams)

	if RaycastResult then
		local HitPosition = RaycastResult.Position + (RaycastResult.Normal * CollisionRadius)
		local Correction = HitPosition - self._CurrentCFrame.Position

		CameraCFrameInSubjectSpace = CameraCFrameInSubjectSpace + (-VecToFocus.Unit * Correction.Magnitude)
	end

	-- Set Camera CFrame

	self._CurrentCFrame = RootPartUnrotatedCFrame * CameraCFrameInSubjectSpace
	self._CurrentCamera.CFrame = self._CurrentCFrame

	-- Apply Character Rotation to match Camera (if needed)

	if self._IsHumanoidControllable() == true or true then
		self._CurrentHumanoid.AutoRotate = false
		self._CurrentRootPart.CFrame = CFrame.Angles(0, self._Yaw, 0) + self._CurrentRootPart.Position -- Rotate character to be upright and facing the same direction as camera
	end

	self:_HandleCharacterTrasparency()
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
	return CornerPos.Magnitude
end

function SUCamera:_IsHumanoidControllable() end

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
		self._CurrentHumanoid = Humanoid
		self._CurrentRootPart = Humanoid.RootPart
		self.RaycastChannel:AppendToFDI(Character)
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

		self._Janitor:Add(
			Camera:GetPropertyChangedSignal("CameraType"):Connect(function()
				Camera.CameraType = Enum.CameraType.Scriptable
			end),
			"Disconnect",
			"CameraTypeChanged"
		)
	end
end

--// Handle Character Obstructing view //--

function SUCamera:_HandleCharacterTrasparency()
	local Distance = (self._CurrentCFrame.Position - self._CurrentRootPart.Position).Magnitude

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
