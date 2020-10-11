local ShapeEditBuffer = {}

function ShapeEditBuffer.new(shape)
	local buffer = {
		shape = shape,
		values = {},
		dirty = false,
		compare = false
	}
	return setmetatable(buffer, ShapeEditBuffer)
end

function ShapeEditBuffer:__index(index)
	if self.compare then
		return ShapeEditBuffer[index] or self.shape[index]
	end
	return self.values[index] or ShapeEditBuffer[index] or self.shape[index]
end

function ShapeEditBuffer:__newindex(index, value)
	if self.compare then
		self:reset()
	end
	self.values[index] = value
	if index == 'note' then
		self.values.midi_note, self.values.note_name, self.values.note_freq = self.shape:get_note_values(value)
	end
	self.dirty = true
end

function ShapeEditBuffer:apply()
	if not self.compare then
		self.shape.note = self.note
		self.shape.output_mode = self.output_mode
		self.shape.midi_device = self.midi_device
		self.shape.midi_channel = self.midi_channel
	end
	self:reset()
end

function ShapeEditBuffer:undo()
	self.compare = not self.compare
end

function ShapeEditBuffer:reset()
	self.values.note = nil
	self.values.midi_note = nil
	self.values.note_name = nil
	self.values.note_freq = nil
	self.values.output_mode = nil
	self.values.midi_device = nil
	self.values.midi_channel = nil
	self.dirty = false
	self.compare = false
end

local Shape = {}

local next_id = 1

function Shape.new(note, n, r, x, rate)
	local shape = {
		id = next_id,
		_note = 1,
		note_name = 'A3',
		note_freq = 440,
		output_mode = o_ENGINE,
		midi_note = 69,
		midi_device = 1,
		midi_channel = 1,
		mute = true,
		_n = 0,
		_r = r,
		r_strike_min = 0,
		delta_x = 0,
		x = x,
		nx = x,
		rate = rate,
		theta = 0,
		vertices = {},
		side_levels = {},
		voices = {}
	}
	shape.edits = ShapeEditBuffer.new(shape)
	setmetatable(shape, Shape)
	-- initialize with 'n' sides and note 'note'
	shape.r = r
	shape.n = n
	shape.note = note
	next_id = next_id + 1
	return shape
end

function Shape:get_note_values(note)
	local scale_degrees = #scale
	local degree = (note - 1) % #scale + 1
	local octave = math.floor((note - 1) / #scale)
	local note_num = util.clamp(scale[degree] + octave * 12, 0, 127)
	-- font 2 doesn't have a real 'sharp' character
	local note_name = string.gsub(musicutil.note_num_to_name(note_num, true), '♯', '#')
	local note_freq = musicutil.note_num_to_freq(note_num)
	return note_num, note_name, note_freq
end

function Shape:__newindex(index, value)
	if index == 'n' then
		self._n = value
		self:calculate_points()
		self:calculate_strike_radius()
	elseif index == 'r' then
		self._r = value
		self:calculate_strike_radius()
	elseif index == 'note' then
		self._note = value -- TODO: clamp here instead of in get_note_values()
		self.midi_note, self.note_name, self.note_freq = self:get_note_values(value)
	end
end

function Shape:__index(index)
	if index == 'n' then
		return self._n
	elseif index == 'r' then
		return self._r
	elseif index == 'note' then
		return self._note
	end
	return Shape[index]
end

function Shape:calculate_points()
	local vertex_angle = tau / self.n
	for v = 1, self.n do
		local vertex = self.vertices[v]
		-- initialize if necessary
		if vertex == nil then
			vertex = {
				level = 0
			}
			self.vertices[v] = vertex
			self.side_levels[v] = self.side_levels[v] or 0
		end
		-- calculate next x and y
		local nx = self.nx + math.cos(self.theta + v * vertex_angle) * self.r
		local ny = y_center + math.sin(self.theta + v * vertex_angle) * self.r
		-- apply previous frame's 'next' values, if any
		vertex.x = vertex.nx or nx
		vertex.y = vertex.ny or ny
		-- save next values for next frame
		vertex.nx = nx
		vertex.ny = ny
	end
end

function Shape:calculate_strike_radius()
	if self.n == 1 then
		-- special case for point 'polygons', because rounding error (or something) makes the below not return 0
		self.r_strike_min = self.r
	else
		self.r_strike_min = math.cos(math.pi - math.pi * (self.n - 1) / self.n) * self.r
	end
end

function Shape:tick()
	self.x = self.nx
	self.nx = self.nx + self.delta_x
	self.delta_x = 0
	self.theta = self.theta + self.rate
	while self.theta > tau do
		self.theta = self.theta - tau
	end
	self:calculate_points()
end

function Shape:update_guide_for_intersection(other, level)
	-- constants used below
	local diff = self.x^2 - other.x^2
	local div = 2 * (other.x - self.x)
	-- x coordinate of intersection between the two shapes' outer bounds
	local outer = (self.r^2 - other.r^2 - diff) / div
	-- x coordinate of intersection between this shape's outer bound and other shape's inner bound
	local self_other = (self.r^2	- other.r_strike_min^2 - diff) / div
	-- x coordinate of intersection between this shape's inner bound and other shape's outer bound
	local other_self = (self.r_strike_min^2	- other.r^2 - diff) / div
	local self_other_min = math.max(math.min(outer, self_other), self.x - self.r, other.x - other.r)
	local self_other_max = math.min(math.max(outer, self_other), self.x + self.r, other.x + other.r)
	local other_self_min = math.max(math.min(outer, other_self), self.x - self.r, other.x - other.r)
	local other_self_max = math.min(math.max(outer, other_self), self.x + self.r, other.x + other.r)
	for x = math.floor(math.min(self_other_min, other_self_min)), math.ceil(math.max(self_other_max, other_self_max)) do
		guide.other_edit[x] = math.max(guide.other_edit[x], math.min(x - self_other_min, self_other_max - x + 1))
		guide.edit_other[x] = math.max(guide.edit_other[x], math.min(x - other_self_min, other_self_max - x + 1))
	end
end

--[[
function Shape:draw_strike_zone(selected, level)
	if self.n == 1 then
		screen.circle(self.x, y_center, self.r)
		screen.line_width(1)
		screen.level(math.floor((selected and 4 or 2) * level + 0.5))
		screen.stroke()
		return
	end
	if not self.mute then
		local r = (self.r + self.r_strike_min) / 2
		-- screen.close() -- TODO
		screen.circle(self.x, y_center, r)
		screen.line_width(math.max(1, self.r - self.r_strike_min))
		screen.level(math.floor(((selected and not self.mute) and 4 or 2) * level + 0.5))
		screen.stroke()
	else
		screen.level(math.floor((selected and 6 or 2) * level + 0.5))
		screen.line_width(1)
		screen.circle(self.x, y_center, self.r)
		screen.stroke()
		screen.circle(self.x, y_center, self.r_strike_min)
		screen.stroke()
	end
end
--]]

function Shape:draw_lines(selected, dim)
	if self.mute then
		return
	end
	local n = self.n
	if n == 2 then
		n = 1
	end
	for v = 1, n do
		local vertex1 = self.vertices[v]
		local vertex2 = self.vertices[v % self.n + 1]
		local level = self.side_levels[v]
		if self.n == 2 then
			level = math.max(level, self.side_levels[v + 1])
		end
		if selected then
			level = 1 - (1 - level) * 0.6
		end
		screen.move(vertex1.x, vertex1.y)
		screen.line(vertex2.x, vertex2.y)
		if dim then
			screen.level(math.floor(2 + level * 4))
		else
			screen.level(math.floor(2 + level * 13))
		end
		screen.line_width(math.max(1, level * 2.5))
		screen.stroke()
	end
end

function Shape:draw_points(selected, dim)
	for v = 1, self.n do
		local vertex = self.vertices[v]
		local level = vertex.level
		if selected then
			level = 1 - (1 - level) * 0.8
		end
		screen.circle(vertex.x, vertex.y, 0.5 + level * 3)
		if dim then
			screen.level(math.floor(3 + level * 9))
		else
			screen.level(math.floor(6 + level * 9))
		end
		screen.fill()
	end
	if selected then
		local x_clamped = util.clamp(self.x, 0, 128)
		if self.mute then
			screen.circle(x_clamped, y_center, 1.55)
			screen.level(4)
			screen.stroke()
		else
			screen.circle(x_clamped, y_center, 1.1)
			screen.level(10)
			screen.fill()
		end
	end
end

-- check whether a moving point will intercept a moving line between now and
-- the next animation frame
function calculate_point_segment_intersection(v1, v2a, v2b, x_center, n)
	-- two vectors expressible in terms of t (time), using nx,ny and x,y: v2a to v1, and v2a to v2b
	-- if their cross product is zero at any point in time, that's when they collide

	local t, vel

	if v2a.nx == v2a.x and v2a.ny == v2a.y and v2b.nx == v2b.x and v2b.ny == v2b.y then
		-- special case if v2a and v2b aren't moving: cross product won't involve t^2, so quadratic
		-- formula won't work; we can just solve for t:
		local d1x = v1.x - v2a.x
		local d1y = v1.y - v2a.y
		local dd1x = v1.nx - v1.x
		local dd1y = v1.ny - v1.y
		local d2x = v2b.x - v2a.x
		local d2y = v2b.y - v2a.y
		-- coefficients of t and t^0, just like below ('a' would be 0)
		local b = dd1x * d2y - dd1y * d2x
		local c = d1x * d2y - d1y * d2x
		t = -c / b
		if t < 0 or t > 1 then
			return nil
		end
		-- velocity is, as below, the derivative of the cross product
		vel = b
	else
		-- if everything's moving, we'll have to do this the hard way

		-- distances used repeatedly below
		local d1x = v1.x - v2a.x
		local d1y = v1.y - v2a.y
		local dd1x = v1.nx - v2a.nx - d1x
		local dd1y = v1.ny - v2a.ny - d1y
		local d2x = v2b.x - v2a.x
		local d2y = v2b.y - v2a.y
		local dd2x = v2b.nx - v2a.nx - d2x
		local dd2y = v2b.ny - v2a.ny - d2y

		-- coefficients of t^2, t, and t^0 in cross product, worked out by hand
		local a = dd1x * dd2y - dd1y * dd2x
		local b = dd2y * d1x + dd1x * d2y - dd2x * d1y - dd1y * d2x
		local c = d2y * d1x - d2x * d1y

		-- now we'll plug all of this into the quadratic formula...
		-- a negative discriminant means there's no solution (no intersection). bail.
		local discriminant = b * b - 4 * a * c
		if discriminant < 0 then
			return nil
		end

		local sqrt = math.sqrt(discriminant)
		t = (-b + sqrt) / (2 * a)
		-- we're looking for a solution in the range [0, 1], so if one of the two possible solutions
		-- doesn't fit, try the other, and if that doesn't fit, give up
		if t < 0 or t > 1 then
			t = (-b - sqrt) / (2 * a)
		end
		if t < 0 or t > 1 then
			return nil
		end
		-- velocity is the derivative of the cross product
		vel = 2 * a * t + b
	end

	-- now check that, at time t, v1 actually intersects with line segment v2a v2b (as opposed to
	-- somewhere else on the line described by the two points)
	local v1xt  =  v1.x + t * ( v1.nx - v1.x)
	local v1yt  =  v1.y + t * ( v1.ny - v1.y)
	local v2axt = v2a.x + t * (v2a.nx - v2a.x)
	local v2ayt = v2a.y + t * (v2a.ny - v2a.y)
	local v2bxt = v2b.x + t * (v2b.nx - v2b.x)
	local v2byt = v2b.y + t * (v2b.ny - v2b.y)
	local pos = (v1xt - math.min(v2axt, v2bxt)) / math.abs(v2axt - v2bxt)
	if pos >= 0 and pos <= 1 then
		-- it's a hit! was v1 moving into or out of the shape whose vertices include v2a and v2b?
		-- but first: a special case for 2-sided 'polygons' (lines), where the center product below
		-- "should" be exactly zero, but may not be due to rounding error: there's no such thing as
		-- moving into or out of the shape anyway, so we should count all collisions
		if n > 2 then
			-- find direction (inward or outward) by comparing the signs of the velocity and the cross
			-- product between the side and the shape's center point
			local center_product = (x_center - v2axt) * (v2byt - v2ayt) - (y_center - v2ayt) * (v2bxt - v2axt)
			local inward = (vel > 0 and center_product > 0) or (vel < 0 and center_product < 0)
			-- skip inner- or outer-moving collisions if the params tell us to
			if (trigger_style == s_IN) and not inward then
				return nil
			elseif (trigger_style == s_OUT) and inward then
				return nil
			end
		end
		return t, pos, vel, v1xt, v1yt
	end

	return nil
end

-- check whether any of this shape's points will touch another shape's sides
-- between now and the next animation frame
function Shape:check_intersection(other)

	-- if either shape is muted, skip calculation
	if (mute_style == m_BOTH and self.mute) or other.mute then
		return
	end

	-- if shapes are too far apart to intersect, skip calculation
	if math.max(self.x, self.nx) + self.r < math.min(other.x, other.nx) - other.r then
		return
	elseif math.max(other.x, other.nx) + other.r < math.min(self.x, self.nx) - self.r then
		return
	end

	for v = 1, self.n do
		local vertex1 = self.vertices[v]

		local sides = other.n
		-- special case for "two-sided" "polygon": that's a line, and if we counted
		-- both sides, we'd be counting it twice
		if sides == 2 then
			sides = 1
		end

		for s = 1, sides do
			-- TODO: it's probably a waste of time to do this for every pair of segments...
			local vertex2a = other.vertices[s]
			local vertex2b = other.vertices[s % other.n + 1]
			local t, pos, vel, x, y = calculate_point_segment_intersection(vertex1, vertex2a, vertex2b, other.x, other.n)
			if t ~= nil then
				if t > 0 then
					clock.run(function()
						clock.sleep(t * rate)
						handle_strike(other, s, pos, vel, x, y, self, v)
					end)
				else
					handle_strike(other, s, pos, vel, x, y, self, v)
				end
				other.side_levels[s] = 1
				vertex1.level = 1
			end
		end
	end
end

return Shape