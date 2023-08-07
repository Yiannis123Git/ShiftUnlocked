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
]]

--// Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local JanitorModule = require(ReplicatedStorage.Packages.Janitor)

--// Variables
local GCWarn = true

local SUCamera = {}
SUCamera.__index = SUCamera

type self = {
	FOV: number,
	Enabled: boolean,
	Janitor: JanitorModule.Janitor,
    LockedIcon: string?,
    UnlockedIcon: string?,
}

type SUCamera = typeof(setmetatable({} :: self, SUCamera))

local CameraLog: { SUCamera } = {}

--// Camera Conctructor //--

function SUCamera.new(): SUCamera
	local self = setmetatable({}, SUCamera)

	-- Configurable Parameters

	self.FOV = 70
    self.LockedIcon = nil 
    self.UnlockedIcon = nil

	-- State Variables

	self.Enabled = false

	-- DataModel refrences

	self.Janitor = JanitorModule.new()

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

--// Camera Methods //--

function SUCamera:SetEnabled(Enabled: boolean) -- hook connections for runtime updating and for input catching
	if Enabled == self.Enabled then
		-- No need to perform any action:
		return
	end

	-- Make sure that other cameras are not enabled

	if #CameraLog > 1 then
		for _, Cam in pairs(CameraLog) do
			assert(not Cam.Enabled, "[ShiftUnlocked] There are more than one SUCameras enabled currently")
		end
	end

	-- Bind camera update function to render stepped

	RunService:BindToRenderStep("SUCameraUpdate", Enum.RenderPriority.Camera.Value - 1, function(DT)
		self:Update(DT)
	end)
end

function SUCamera:Update() end

function SUCamera:Destroy()

    -- Unbind camera update function from render stepped

	RunService:UnbindFromRenderStep("SUCameraUpdate")

	-- Remove SUCamera from CameraLog table

	table.remove(CameraLog, self)
end
