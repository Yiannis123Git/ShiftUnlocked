local ConstrainedSpring = {}
ConstrainedSpring.__index = ConstrainedSpring

type ConstrainedSpringProperties = {
	Freq: number, -- Undamped Frequency (Hz)
	CurrentPos: number, -- Current position
	CurrentVelocity: number, -- Current velocity
	MinValue: number, -- Minimum bound
	MaxValue: number, -- Maximum bound
	Goal: number, -- Goal position
}

export type ConstrainedSpring = typeof(setmetatable({} :: ConstrainedSpringProperties, ConstrainedSpring))

function ConstrainedSpring.new(Freq: number, CurrentPos: number, MinValue: number, MaxValue: number): ConstrainedSpring
	local self = setmetatable({} :: ConstrainedSpringProperties, ConstrainedSpring)

	self.Freq = Freq
	self.CurrentPos = math.clamp(CurrentPos, MinValue, MaxValue)
	self.CurrentVelocity = 0
	self.MinValue = MinValue
	self.MaxValue = MaxValue
	self.Goal = CurrentPos

	return self
end

function ConstrainedSpring.Step(self: ConstrainedSpring, DT: number): number
	local Freq = self.Freq * 2 * math.pi -- Convert from Hz to rad/s
	local CurrentPos = self.CurrentPos
	local CurrentVelocity = self.CurrentVelocity
	local MinValue = self.MinValue
	local MaxValue = self.MaxValue
	local Goal = self.Goal

	-- Solve the spring ODE for position and velocity after time t, assuming critical damping:
	--   2*f*x'[t] + x''[t] = f^2*(g - x[t])
	-- Knowns are x[0] and x'[0].
	-- Solve for x[t] and x'[t].

	local Offset = Goal - CurrentPos
	local Step = Freq * DT
	local Decay = math.exp(-Step)

	local NewPos = Goal + (CurrentVelocity * DT - Offset * (Step + 1)) * Decay
	local NewVelocity = ((Offset * Freq - CurrentVelocity) * Step + CurrentVelocity) * Decay

	-- Constrain

	if NewPos < MinValue then
		NewPos = MinValue
		NewVelocity = 0
	elseif NewPos > MaxValue then
		NewPos = MaxValue
		NewVelocity = 0
	end

	self.CurrentPos = NewPos
	self.CurrentVelocity = NewVelocity

	return NewPos
end

return ConstrainedSpring
