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

local SUCamera = {}
SUCamera.__index = SUCamera

type self = {
	FOV: number,
	Enabled: boolean,
}

type SUCamera = typeof(setmetatable({} :: self, SUCamera))

--// Camera Conctructor //--

function SUCamera.new(): SUCamera
	local self = setmetatable({}, SUCamera)

	-- Configurable Parameters

	self.FOV = 70

	-- State Variables

	self.Enabled = false
end

--// Camera Methods //--

function SUCamera:SetEnabled(Enabled: boolean)
	if Enabled == self.Enabled then
		-- No need to perform any action:
		return
	end
end
