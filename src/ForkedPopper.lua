--!strict

--// Modules
local JanitorModule = require(script.Parent.Parent.janitor)

--// Variables
local Janitor = JanitorModule.new()
local CurrentCamera = game.Workspace.CurrentCamera
local NearPlaneZ, ProjX, ProjY

local Popper = {}
Popper.ActiveSUCamera = nil

local tan = math.tan
local rad = math.rad
local inf = math.huge

function UpdateProjection() -- Update vertical and horizontal dimensions of the near plane (Measured in studs)
	local FOV = rad(CurrentCamera.FieldOfView) -- Y Axis FOV
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

--// Query Point //--

-- Query a point in world space and return the limit

function QueryPoint(Origin: Vector3, UnitDirection: Vector3, Distance: number)
	Distance = Distance + NearPlaneZ -- We need to offset the distance by the near plane Z to get the actual distance from the camera
	local Target = Origin + UnitDirection * Distance

	-- Init limit to infinity (No Limit)

	local Limit = inf

	-- Collision Check

	local RaycastResult = (Popper.ActiveSUCamera :: any).RaycastChannel:Cast(Origin, Target - Origin)

	if RaycastResult then
		Limit = (RaycastResult.Position - Origin).Magnitude
	end

	return Limit - NearPlaneZ
end

--// Query Viewport //--

-- Query all viewport corners in world space and return the strictest limit

function QueryViewport(Focus: CFrame, Distance: number)
	local FP = Focus.Position
	local FX = Focus.RightVector
	local FY = Focus.UpVector
	local FZ = -Focus.LookVector

	local BoxLimit = inf

	-- Center the viewport on the PoI, sweep points on the edge towards the target, and take the minimum limits
	for ViewX = 0, 1 do
		local WorldX = FX * ((ViewX - 0.5) * ProjX)

		for ViewY = 0, 1 do
			local worldY = FY * ((ViewY - 0.5) * ProjY)

			local Origin = FP + NearPlaneZ * (WorldX + worldY) -- Viewport Corner in world space (4 total corners)
			local Limit = QueryPoint(Origin, FZ, Distance)

			if Limit < BoxLimit then
				BoxLimit = Limit
			end
		end
	end

	return BoxLimit
end

--// Get Distance (Popper) //--

-- Returns the Maximum Distance from the Focus Point that the camera can have without clipping

function Popper.GetDistance(Focus: CFrame, TargetDistance: number): number
	local Distance = TargetDistance
	local QueryResult = QueryViewport(Focus, TargetDistance)

	if QueryResult < Distance then
		Distance = QueryResult
	end

	return Distance
end

return Popper
