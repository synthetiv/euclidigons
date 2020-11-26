local Shape = {}
Shape.__index = Shape

local next_id = 1

function Shape.new(param_group)
	local shape = {
		id = next_id,
		output_mode = o_ENGINE,
		midi_device = 1,
		midi_channel = 1,
		n = 0,
		r = 0,
		x = 0,
		nx = 0,
		theta = 0,
		vertices = {},
		side_levels = {},
		voices = {},
		params = param_group
	}
	setmetatable(shape, Shape)
	param_group.shape = shape
	param_group.in_use = 1
	param_group:update_shape()
	next_id = next_id + 1
	return shape
end

function Shape:update_params()
	for i, id in ipairs(self.params.param_ids) do
		if id ~= 'in_use' then
			self.params[id] = self[id]
		end
	end
end

function Shape:get_note_values(note)
	local scale_degrees = #scale
	local degree = (note - 1) % #scale + 1
	local octave = math.floor((note - 1) / #scale)
	local note_num = util.clamp(scale[degree] + octave * 12, 0, 127)
	local note_name = musicutil.note_num_to_name(note_num, true)
	local note_freq = musicutil.note_num_to_freq(note_num)
	return note_num, note_name, note_freq
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

function Shape:calculate_area()
	local area = 0
	for v = 1, self.n do
		local vertex = self.vertices[v]
		local vertex2 = self.vertices[v % self.n + 1]
		area = area + vertex.x * vertex2.y - vertex2.x * vertex.y
	end
	self.area = area
end

function Shape:free()
	-- release/free voices
	local voices = self.voices
	for v, voice in ipairs(voices) do
		voice:release()
	end
	-- unlink from param group
	self.params.shape = nil
	self.params.in_use = 0
end

function Shape:tick()
	self.x = self.nx
	self.params.theta = self.theta + (self.rate * tau * rate)
	while self.theta > tau do
		self.theta = self.theta - tau
	end
	self:calculate_points()
end

function Shape:is_active()
	return self.active == 1
end

function Shape:draw_lines(selected, dim)
	if not self:is_active() then
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
		if n == 2 then
			level = math.max(self.side_levels[v + 1])
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
		if not self:is_active() then
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
	if (mute_style == m_BOTH and not self:is_active()) or not other:is_active() then
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