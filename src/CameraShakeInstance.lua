-- Camera Shake Instance
-- Stephen Leitnick
-- February 26, 2018

--[[
	
	cameraShakeInstance = CameraShakeInstance.new(magnitude, roughness, fadeInTime, fadeOutTime)
	
--]]

--// Yiannis123: Applied typechecking and kennethloeffler's pull request "https://github.com/Sleitnick/RbxCameraShaker/pull/6" //--

local TICK_RATE = 1 / 60

local CameraShakeInstance = {}
CameraShakeInstance.__index = CameraShakeInstance

type CameraShakeInstanceProperties = {
	Magnitude: number,
	Roughness: number,
	PositionInfluence: Vector3,
	RotationInfluence: Vector3,
	DeleteOnInactive: boolean,
	roughMod: number,
	magnMod: number,
	fadeOutDuration: number,
	fadeInDuration: number,
	sustain: boolean,
	currentFadeTime: number,
	tick: number,
	_accumulator: number,
	_camShakeInstance: boolean,
}

export type CameraShakeInstance = typeof(setmetatable({} :: CameraShakeInstanceProperties, CameraShakeInstance))

local V3 = Vector3.new
local NOISE = math.noise

CameraShakeInstance.CameraShakeState = {
	FadingIn = 0,
	FadingOut = 1,
	Sustained = 2,
	Inactive = 3,
}

function CameraShakeInstance.new(
	magnitude: number,
	roughness: number,
	fadeInTime: number?,
	fadeOutTime: number?
): CameraShakeInstance
	if fadeInTime == nil then
		fadeInTime = 0
	end
	if fadeOutTime == nil then
		fadeOutTime = 0
	end

	assert(type(magnitude) == "number", "Magnitude must be a number")
	assert(type(roughness) == "number", "Roughness must be a number")
	assert(type(fadeInTime) == "number", "FadeInTime must be a number")
	assert(type(fadeOutTime) == "number", "FadeOutTime must be a number")

	local self = setmetatable({
		Magnitude = magnitude,
		Roughness = roughness,
		PositionInfluence = V3(),
		RotationInfluence = V3(),
		DeleteOnInactive = true,
		roughMod = 1,
		magnMod = 1,
		fadeOutDuration = fadeOutTime,
		fadeInDuration = fadeInTime,
		sustain = (fadeInTime > 0),
		currentFadeTime = (fadeInTime > 0 and 0 or 1),
		tick = Random.new():NextNumber(-100, 100),
		_accumulator = 0,
		_camShakeInstance = true,
	}, CameraShakeInstance)

	return self
end

function CameraShakeInstance._UpdateShake(self: CameraShakeInstance, dt: number)
	local _tick = self.tick
	local currentFadeTime = self.currentFadeTime

	local offset = V3(NOISE(_tick, 0) * 0.5, NOISE(0, _tick) * 0.5, NOISE(_tick, _tick) * 0.5)

	self._accumulator += dt

	while self._accumulator >= TICK_RATE do
		self._accumulator -= TICK_RATE

		if self.fadeInDuration > 0 and self.sustain then
			if currentFadeTime < 1 then
				currentFadeTime = currentFadeTime + (TICK_RATE / self.fadeInDuration)
			elseif self.fadeOutDuration > 0 then
				self.sustain = false
			end
		end

		if not self.sustain then
			currentFadeTime = currentFadeTime - (TICK_RATE / self.fadeOutDuration)
		end

		if self.sustain then
			self.tick = _tick + (TICK_RATE * self.Roughness * self.roughMod)
		else
			self.tick = _tick + (TICK_RATE * self.Roughness * self.roughMod * currentFadeTime)
		end
	end

	self.currentFadeTime = currentFadeTime

	return offset * self.Magnitude * self.magnMod * currentFadeTime
end

function CameraShakeInstance.StartFadeOut(self: CameraShakeInstance, fadeOutTime)
	if fadeOutTime == 0 then
		self.currentFadeTime = 0
	end
	self.fadeOutDuration = fadeOutTime
	self.fadeInDuration = 0
	self.sustain = false
end

function CameraShakeInstance.StartFadeIn(self: CameraShakeInstance, fadeInTime: number?)
	if fadeInTime == 0 then
		self.currentFadeTime = 1
	end
	self.fadeInDuration = fadeInTime or self.fadeInDuration
	self.fadeOutDuration = 0
	self.sustain = true
end

function CameraShakeInstance.GetScaleRoughness(self: CameraShakeInstance)
	return self.roughMod
end

function CameraShakeInstance.SetScaleRoughness(self: CameraShakeInstance, v)
	self.roughMod = v
end

function CameraShakeInstance.GetScaleMagnitude(self: CameraShakeInstance)
	return self.magnMod
end

function CameraShakeInstance.SetScaleMagnitude(self: CameraShakeInstance, v)
	self.magnMod = v
end

function CameraShakeInstance.GetNormalizedFadeTime(self: CameraShakeInstance)
	return self.currentFadeTime
end

function CameraShakeInstance.IsShaking(self: CameraShakeInstance)
	return (self.currentFadeTime > 0 or self.sustain)
end

function CameraShakeInstance.IsFadingOut(self: CameraShakeInstance)
	return ((not self.sustain) and self.currentFadeTime > 0)
end

function CameraShakeInstance.IsFadingIn(self: CameraShakeInstance)
	return (self.currentFadeTime < 1 and self.sustain and self.fadeInDuration > 0)
end

function CameraShakeInstance.GetState(self: CameraShakeInstance)
	if self:IsFadingIn() then
		return CameraShakeInstance.CameraShakeState.FadingIn
	elseif self:IsFadingOut() then
		return CameraShakeInstance.CameraShakeState.FadingOut
	elseif self:IsShaking() then
		return CameraShakeInstance.CameraShakeState.Sustained
	else
		return CameraShakeInstance.CameraShakeState.Inactive
	end
end

return CameraShakeInstance
