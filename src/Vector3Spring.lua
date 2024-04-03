--[[
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
]]

--// Credit to DervexHero and Fraktality for their original code //--
--// This code is derivied from https://github.com/DervexDev/AdvancedSpring //--

local V3 = {}
V3.__index = V3

type V3Properties = {
	X: number,
	Y: number,
	Z: number,
}

type V3 = typeof(setmetatable({} :: V3Properties, V3))

function V3.new(X: number, Y: number, Z: number): V3
	local self = setmetatable({} :: V3Properties, V3)

	self.X = X
	self.Y = Y
	self.Z = Z

	return self
end

function V3.__add(self: V3, OtherV3: V3)
	local ProducedV3 = V3.new(self.X, self.Y, self.Z)

	ProducedV3.X += OtherV3.X
	ProducedV3.Y += OtherV3.Y
	ProducedV3.Z += OtherV3.Z

	return ProducedV3
end

function V3.__sub(self: V3, OtherV3: V3)
	local ProducedV3 = V3.new(self.X, self.Y, self.Z)

	ProducedV3.X -= OtherV3.X
	ProducedV3.Y -= OtherV3.Y
	ProducedV3.Z -= OtherV3.Z

	return ProducedV3
end

function V3.__mul(self: V3, Scaler)
	local ProducedV3 = V3.new(self.X, self.Y, self.Z)

	ProducedV3.X *= Scaler
	ProducedV3.Y *= Scaler
	ProducedV3.Z *= Scaler

	return ProducedV3
end

function V3.__div(V3: V3, Scaler)
	local ProducedV3 = V3.new(V3.X, V3.Y, V3.Z)

	ProducedV3.X /= Scaler
	ProducedV3.Y /= Scaler
	ProducedV3.Z /= Scaler

	return ProducedV3
end

local LinearSpring = {}
LinearSpring.__index = LinearSpring

type LinearSpringProperties = {
	Damping: number,
	Frequency: number,
	Goal: V3,
	Position: V3,
	Velocity: V3,
}

type LinearSpring = typeof(setmetatable({} :: LinearSpringProperties, LinearSpring))

function LinearSpring.new(Damping: number, Frequency: number, Goal: V3): LinearSpring
	local self = setmetatable({} :: LinearSpringProperties, LinearSpring)

	self.Damping = Damping
	self.Frequency = Frequency
	self.Goal = Goal
	self.Position = Goal
	self.Velocity = Goal * 0

	return self
end

function LinearSpring.Step(self: LinearSpring, DT: number): V3
	local Damping = self.Damping
	local Frequency = self.Frequency
	local Goal = self.Goal
	local Position = self.Position
	local Velocity = self.Velocity

	local Offset = Position - Goal
	local Decay = math.exp(-DT * Damping * Frequency)

	if Damping == 1 then
		self.Position = (Velocity * DT + Offset * (Frequency * DT + 1)) * Decay + Goal
		self.Velocity = (Velocity - (Offset * Frequency + Velocity) * (Frequency * DT)) * Decay
	elseif Damping < 1 then
		local c = math.sqrt(1 - Damping * Damping)

		local i = math.cos(DT * Frequency * c)
		local j = math.sin(DT * Frequency * c)

		self.Position = (Offset * i + (Velocity + Offset * (Damping * Frequency)) * j / (Frequency * c)) * Decay + Goal
		self.Velocity = (Velocity * (i * c) - (Velocity * Damping + Offset * Frequency) * j) * (Decay / c)
	else
		local c = math.sqrt(Damping * Damping - 1)

		local r1 = -Frequency * (Damping - c)
		local r2 = -Frequency * (Damping + c)

		local co2 = (Velocity - Offset * r1) / (2 * Frequency * c)
		local co1 = Offset - co2

		local e1 = co1 * math.exp(r1 * DT)
		local e2 = co2 * math.exp(r2 * DT)

		self.Position = e1 + e2 + Goal
		self.Velocity = r1 * e1 + r2 * e2
	end

	return self.Position
end

function ConvertVector3(ToConvert: Vector3): V3
	return V3.new(ToConvert.X, ToConvert.Y, ToConvert.Z)
end

function ConvertV3(ToConvert: V3): Vector3
	return Vector3.new(ToConvert.X, ToConvert.Y, ToConvert.Z)
end

local Vector3Spring = {}
Vector3Spring.__index = Vector3Spring

type Vector3SpringProperties = {
	Spring: LinearSpring,
}

export type Vector3Spring = typeof(setmetatable({} :: Vector3SpringProperties, Vector3Spring))

function Vector3Spring.new(Frequency: number, Damping: number): Vector3Spring
	local self = setmetatable({} :: Vector3SpringProperties, Vector3Spring)

	self.Spring = LinearSpring.new(Damping, Frequency, V3.new(0, 0, 0))

	return self
end

function Vector3Spring.SetGoal(self: Vector3Spring, Goal: Vector3)
	self.Spring.Goal = ConvertVector3(Goal)
end

function Vector3Spring.Step(self: Vector3Spring, DT: number)
	local CurrentPosition = self.Spring:Step(DT)

	return ConvertV3(CurrentPosition)
end

function Vector3Spring.Reset(self: Vector3Spring, CurrentPosition: Vector3) -- Sets the spring to a dormant state
	self.Spring.Position = ConvertVector3(CurrentPosition)
	self.Spring.Velocity = ConvertVector3(Vector3.new(0, 0, 0))
	self.Spring.Goal = ConvertVector3(CurrentPosition)
end

function Vector3Spring.GetDisplacement(self: Vector3Spring): number
	return (ConvertV3(self.Spring.Goal) - ConvertV3(self.Spring.Position)).Magnitude
end

return Vector3Spring
