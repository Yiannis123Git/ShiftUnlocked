--!strict

--// Modules
local JanitorModule = require(script.Parent.Parent.janitor)

--// Variables
local Janitor = JanitorModule.new()
local CurrentCamera = game.Workspace.CurrentCamera
local NearPlaneZ, ProjX, ProjY

local Popper = {}
Popper.ActiveSUCamera = nil

local min = math.min
local tan = math.tan
local rad = math.rad
local inf = math.huge

function UpdateProjection()
	local FOV = rad(CurrentCamera.FieldOfView)
	local View = CurrentCamera.ViewportSize
	local AspectRatio = View.X / View.Y -- Aspect Ratio

	ProjY = 2 * tan(FOV / 2)
	ProjX = AspectRatio * ProjY
end

function OnCurrentCameraChanged(Camera: Camera?)
	CurrentCamera = Camera

	if Camera ~= nil then
		Janitor:Add(
			Camera:GetPropertyChangedSignal("FieldOfView"):Connect(UpdateProjection),
			"Disconnect",
			"FieldOfViewChanged"
		)

		Janitor:Add(
			Camera:GetPropertyChangedSignal("ViewportSize"):Connect(UpdateProjection),
			"Disconnect",
			"ViewportSizeChanged"
		)

		Janitor:Add(
			Camera:GetPropertyChangedSignal("NearPlaneZ"):Connect(function()
				NearPlaneZ = CurrentCamera.NearPlaneZ
			end),
			"Disconnect",
			"NearPlaneZChanged"
		)

		UpdateProjection()

		NearPlaneZ = CurrentCamera.NearPlaneZ
	end
end

function Popper.SetEnabled(Enabled: boolean)
	if Enabled == true then
		Janitor:Add(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(OnCurrentCameraChanged), "Disconnect")

		OnCurrentCameraChanged(game.Workspace.CurrentCamera)
	else
		Janitor:Cleanup()
	end
end

--// Get Collision Point //--

function GetCollisionPoint(Origin, Direction)
	local RaycastResult =
		workspace:Raycast(Origin, Direction, Popper.ActiveSUCamera and Popper.ActiveSUCamera.RaycastChannel.RayParams)

	if RaycastResult then
		return RaycastResult.Position, true
	end

	return Origin + Direction, false
end

--// Query Point //--

local QueryPointParams = RaycastParams.new()
QueryPointParams.FilterType = Enum.RaycastFilterType.Include
QueryPointParams.IgnoreWater = true

function QueryPoint(Origin: Vector3, UnitDirection: Vector3, Distance: number, LastPosition: Vector3?)
	Distance = Distance + NearPlaneZ
	local Target = Origin + UnitDirection * Distance

	local SoftLimit = inf
	local HardLimit = inf

	local RaycastResult = workspace:Raycast(
		Origin,
		Target - Origin,
		Popper.ActiveSUCamera and Popper.ActiveSUCamera.RaycastChannel.RayParams
	)

	if RaycastResult then
		QueryPointParams.FilterDescendantsInstances = { RaycastResult.Instance }

		local ExitResult = workspace:Raycast(Target, RaycastResult.Position - Target, QueryPointParams)

		local Limit = (RaycastResult.Position - Origin).Magnitude

		if ExitResult then
			local Promote = false

			if LastPosition then
				Promote = workspace:Raycast(LastPosition, Target - LastPosition, QueryPointParams)
					or workspace:Raycast(Target, LastPosition - Target, QueryPointParams)
			end

			if Promote then
				-- Ostensibly a soft limit, but the camera has passed through it in the last frame, so promote to a hard limit.
				HardLimit = Limit
			elseif Distance < SoftLimit then
				SoftLimit = Limit
			end
		else
			-- Trivial hard limit
			HardLimit = Limit
		end
	end

	return SoftLimit - NearPlaneZ, HardLimit - NearPlaneZ
end

--// Query Viewport //--

function QueryViewport(Focus: CFrame, Distance: number)
	local FP = Focus.Position
	local FX = Focus.RightVector
	local FY = Focus.UpVector
	local FZ = -Focus.LookVector

	local ViewportSize = CurrentCamera.ViewportSize

	local HardBoxLimit = inf
	local SoftBoxLimit = inf

	-- Center the viewport on the PoI, sweep points on the edge towards the target, and take the minimum limits
	for ViewX = 0, 1 do
		local WorldX = FX * ((ViewX - 0.5) * ProjX)

		for ViewY = 0, 1 do
			local worldY = FY * ((ViewY - 0.5) * ProjY)

			local Origin = FP + NearPlaneZ * (WorldX + worldY)
			local LastPosition = CurrentCamera:ViewportPointToRay(ViewportSize.X * ViewX, ViewportSize.Y * ViewY).Origin

			local SoftPointLimit, HardPointLimit = QueryPoint(Origin, FZ, Distance, LastPosition)

			if HardPointLimit < HardBoxLimit then
				HardBoxLimit = HardPointLimit
			end

			if SoftPointLimit < SoftBoxLimit then
				SoftBoxLimit = SoftPointLimit
			end
		end
	end

	return SoftBoxLimit, HardBoxLimit
end

--// Test Promotion //--

local ScanSampleOffsets = { -- Offsets for the volume visibility test
	Vector2.new(0.4, 0.0),
	Vector2.new(-0.4, 0.0),
	Vector2.new(0.0, -0.4),
	Vector2.new(0.0, 0.4),
	Vector2.new(0.0, 0.2),
}

function TestPromotion(
	Focus: CFrame,
	Distance: number,
	FocusExtrapolation: { Extrapolate: (number) -> CFrame, PosVelocity: Vector3, RotVelocity: Vector3 }
)
	local FP = Focus.Position
	local FX = Focus.RightVector
	local FY = Focus.UpVector
	local FZ = -Focus.LookVector

	-- Dead reckoning the camera rotation and focus

	local SampleDT = 0.0625
	local SampleMaxT = 1.25

	local MaxDistance = (GetCollisionPoint(FP, FocusExtrapolation.PosVelocity * SampleMaxT) - FP).Magnitude

	local CombinedSpeed = FocusExtrapolation.PosVelocity.Magnitude -- Metric that decides how many samples to take

	for DT = 0, min(SampleMaxT, FocusExtrapolation.RotVelocity.Magnitude + MaxDistance / CombinedSpeed), SampleDT do
		local CFDT = FocusExtrapolation.Extrapolate(DT) -- Extrapolated CFrame at time dt in future
		if QueryPoint(CFDT.Position, -CFDT.LookVector, Distance) >= Distance then
			return false
		end
	end

	-- Test screen-space offsets from the focus for the presence of soft limits

	for _, Offset in ipairs(ScanSampleOffsets) do
		local Position = GetCollisionPoint(FP, FX * Offset.X + FY * Offset.Y)

		if QueryPoint(Position, (FP + FZ * Distance - Position).Unit, Distance) == inf then
			return false
		end
	end

	return true
end

--// Get Distance (Popper) //--

-- Returns the Maximum Distance from the Focus Point that the camera can have without clipping

function Popper.GetDistance(Focus: CFrame, TargetDistance: number, FocusExtrapolation): number
	local Distance = TargetDistance
	local Soft, Hard = QueryViewport(Focus, TargetDistance)

	if Hard < Distance then
		Distance = Hard
	end

	if Soft < Distance and TestPromotion(Focus, TargetDistance, FocusExtrapolation) then
		Distance = Soft
	end

	return Distance
end

return Popper
