local Shape = {}

local next_id = 1

function Shape.new(param_group)
	local shape = {
		id = next_id,
		output_mode = o_ENGINE,
		midi_device = 1,
		midi_channel = 1,
		last_x = 0,
		last_radius = 0,
		last_angle = 0,
		area = 0,
		midi_note = 69,
		note_name = 'A',
		note_freq = 440,
		vertices = {},
		side_levels = {},
		voices = {},
		debug = false,
		param_group = param_group
	}
	setmetatable(shape, Shape)
	param_group.shape = shape
	param_group.in_use = 1
	param_group:update_shape()
	shape.last_x = shape.x
	shape.last_radius = shape.radius
	shape.last_angle = shape.angle
	shape:initialize_points()
	next_id = next_id + 1
	return shape
end

function Shape:__index(index)
	if Shape[index] ~= nil then
		return Shape[index]
	end
	return self.param_group[index]
end

function Shape:__newindex(index, value)
	self.param_group[index] = value
end

function Shape:delta(param, d)
	self.param_group:delta(param, d)
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

function Shape:initialize_points()
	local vertex_angle = tau / self.num_sides
	for v = 1, self.num_sides do
		-- get vertex
		local vertex = self.vertices[v]
		-- initialize if necessary
		if vertex == nil then
			vertex = {
				level = 0
			}
			self.vertices[v] = vertex
		end
		-- set/update current and previous coordinates
		vertex.x = self.x + math.cos(self.angle + v * vertex_angle) * self.radius
		vertex.y = y_center + math.sin(self.angle + v * vertex_angle) * self.radius
		-- travel back in time and pretend this shape had the same number of sides it does now, even if it didn't
		-- (not sure how else to handle changes in # of sides)
		vertex.last_x = self.last_x + math.cos(self.last_angle + v * vertex_angle) * self.last_radius
		vertex.last_y = y_center + math.sin(self.last_angle + v * vertex_angle) * self.last_radius
		-- initialize side level too, if necessary
		self.side_levels[v] = self.side_levels[v] or 0
	end
end

function Shape:update_points()
	local vertex_angle = tau / self.num_sides
	for v = 1, self.num_sides do
		vertex = self.vertices[v]
		-- save current x and y to previous x and y
		vertex.last_x = vertex.x
		vertex.last_y = vertex.y
		-- calculate next x and y
		vertex.x = self.x + math.cos(self.angle + v * vertex_angle) * self.radius
		vertex.y = y_center + math.sin(self.angle + v * vertex_angle) * self.radius
	end
end

function Shape:calculate_area()
	local area = 0
	for v = 1, self.num_sides do
		local vertex = self.vertices[v]
		local vertex2 = self.vertices[v % self.num_sides + 1]
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
	self.param_group.shape = nil
	self.param_group.in_use = 0
	self.param_group:reset_all()
end

function Shape:tick()
	if not self.debug then
		self.last_x = self.x
		self.last_radius = self.radius
	end
	self.last_angle = self.angle
	self.angle = self.last_angle + (self.rate * tau * rate)
	self:update_points(true)
end

function Shape:is_active()
	return self.active == 1
end

function Shape:draw_lines(selected, dim)
	-- TODO: are 2-sided polygons still not drawing/working correctly?
	if not self:is_active() then
		return
	end
	local num_sides = self.num_sides
	if num_sides == 2 then
		num_sides = 1
	end
	for v = 1, num_sides do
		local vertex1 = self.vertices[v]
		local vertex2 = self.vertices[v % self.num_sides + 1]
		local level = self.side_levels[v]
		if self.num_sides == 2 then
			level = math.max(self.side_levels[v + 1])
		end
		if selected then
			level = 1 - (1 - level) * 0.6
		end
		screen.move(vertex1.last_x, vertex1.last_y)
		screen.line(vertex2.last_x, vertex2.last_y)
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
	for v = 1, self.num_sides do
		local vertex = self.vertices[v]
		local level = vertex.level
		if selected then
			level = 1 - (1 - level) * 0.8
		end
		screen.circle(vertex.last_x, vertex.last_y, 0.5 + level * 3)
		if dim then
			screen.level(math.floor(3 + level * 9))
		else
			screen.level(math.floor(6 + level * 9))
		end
		screen.fill()
	end
	if selected then
		local x_clamped = util.clamp(self.last_x, 0, 128)
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
function calculate_point_segment_intersection(v1, v2a, v2b, x_center, num_sides)
	-- two vectors expressible in terms of t (time), using x,y and last_x,last_y: v2a to v1, and v2a to v2b
	-- if their cross product is zero at any point in time, that's when they collide

	local t, vel

	if v2a.last_x == v2a.x and v2a.last_y == v2a.y and v2b.last_x == v2b.x and v2b.last_y == v2b.y then
		-- special case if v2a and v2b aren't moving: cross product won't involve t^2, so quadratic
		-- formula won't work; we can just solve for t:
		local d1x = v1.last_x - v2a.last_x
		local d1y = v1.last_y - v2a.last_y
		local dd1x = v1.x - v1.last_x
		local dd1y = v1.y - v1.last_y
		local d2x = v2b.last_x - v2a.last_x
		local d2y = v2b.last_y - v2a.last_y
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
		local d1x = v1.last_x - v2a.last_x
		local d1y = v1.last_y - v2a.last_y
		local dd1x = v1.x - v2a.x - d1x
		local dd1y = v1.y - v2a.y - d1y
		local d2x = v2b.last_x - v2a.last_x
		local d2y = v2b.last_y - v2a.last_y
		local dd2x = v2b.x - v2a.x - d2x
		local dd2y = v2b.y - v2a.y - d2y

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
	local v1xt  =  v1.last_x + t * ( v1.x - v1.last_x)
	local v1yt  =  v1.last_y + t * ( v1.y - v1.last_y)
	local v2axt = v2a.last_x + t * (v2a.x - v2a.last_x)
	local v2ayt = v2a.last_y + t * (v2a.y - v2a.last_y)
	local v2bxt = v2b.last_x + t * (v2b.x - v2b.last_x)
	local v2byt = v2b.last_y + t * (v2b.y - v2b.last_y)
	local pos = (v1xt - math.min(v2axt, v2bxt)) / math.abs(v2axt - v2bxt)
	if pos >= 0 and pos <= 1 then
		-- it's a hit! was v1 moving into or out of the shape whose vertices include v2a and v2b?
		-- but first: a special case for 2-sided 'polygons' (lines), where the center product below
		-- "should" be exactly zero, but may not be due to rounding error: there's no such thing as
		-- moving into or out of the shape anyway, so we should count all collisions
		if num_sides > 2 then
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
	local max_radius = math.max(self.radius, self.last_radius)
	local other_max_radius = math.max(other.radius, other.last_radius)
	if math.max(self.last_x, self.x) + max_radius < math.min(other.last_x, other.x) - other_max_radius then
		return
	elseif math.max(other.last_x, other.x) + other_max_radius < math.min(self.last_x, self.x) - max_radius then
		return
	end

	for v = 1, self.num_sides do
		local vertex1 = self.vertices[v]

		local num_sides = other.num_sides
		-- special case for "two-sided" "polygon": that's a line, and if we counted
		-- both sides, we'd be counting it twice
		if num_sides == 2 then
			num_sides = 1
		end

		for s = 1, num_sides do
			-- TODO: it's probably a waste of time to do this for every pair of segments...
			local vertex2a = other.vertices[s]
			local vertex2b = other.vertices[s % other.num_sides + 1]
			local t, pos, vel, x, y = calculate_point_segment_intersection(vertex1, vertex2a, vertex2b, other.x, num_sides)
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