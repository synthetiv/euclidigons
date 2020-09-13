-- euclidigons

engine.name = 'PolyPerc'
musicutil = require 'musicutil'

tau = math.pi * 2
y_center = 32.5

local Shape = include 'lib/shape'

function calculate_point_segment_intersection(v1, v2a, v2b)
	-- two vectors expressible in terms of t (time), using nx,ny and x,y: v2a to v1, and v2a to v2b
	-- if their cross product is zero at any point in time, that's when they collide

	local t = -1

	-- special case if v2a and v2b aren't moving: cross product won't involve t^2, so quadratic
	-- formula won't work; we can just solve for t:
	if v2a.nx == v2a.x and v2a.ny == v2a.y and v2b.nx == v2b.x and v2b.ny == v2b.y then

		local d1x = v1.x - v2a.x
		local d1y = v1.y - v2a.y
		local dd1x = v1.nx - v1.x
		local dd1y = v1.ny - v1.y
		local d2x = v2b.x - v2a.x
		local d2y = v2b.y - v2a.y
		t = (d1y * d2x - d1x * d2y) / (dd1x * d2y - dd1y * d2x)
		if t < 0 or t > 1 then
			return nil
		end

	else

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
		
		-- TODO: very peculiar:
		-- this doesn't work correctly when v2a and v2b aren't moving.
		-- what does that mean?
		-- ah-ha: dd2x and dd2y will be zero, so /2a will be a divide by zero
		-- a == 0 does NOT necessarily mean a collision, though
		-- I guess it just means you should use a regular non-moving intercept formula...?
		-- or can you do something with cross products that aren't in terms of t?

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
		
	end
	
	-- now check that, at time t, v1 actually intersects with line segment v2a v2b
	local v1xt  =  v1.x + t * ( v1.nx - v1.x)
	local v1yt  =  v1.y + t * ( v1.ny - v1.y)
	local v2axt = v2a.x + t * (v2a.nx - v2a.x)
	local v2ayt = v2a.y + t * (v2a.ny - v2a.y)
	local v2bxt = v2b.x + t * (v2b.nx - v2b.x)
	local v2byt = v2b.y + t * (v2b.ny - v2b.y)
	if v1xt >= math.min(v2axt, v2bxt) and v1xt <= math.max(v2axt, v2bxt) and v1yt >= math.min(v2ayt, v2byt) and v1yt <= math.max(v2ayt, v2byt) then
		return t, v1xt, v1yt
	end

	return nil
end

function clip_points_to_segment(points, vertexa, vertexb, x_center)
	
	local n_points = #points
	if n_points == 0 then return points end

	local new_points = {}

	-- get slope & intercept of the line containing vertexa and vertexb; we'll use this to eliminate vertices
	-- that can't possibly fall within shape1
	local slope = (vertexb.y - vertexa.y) / (vertexb.x - vertexa.x)
	local intercept = vertexa.y - slope * vertexa.x
	
	for p = 1, n_points do
		local point = points[p]
		-- if both (x_center, y_center) and point are below the line described by slope and intercept,
		-- or both above, add point to the next list.
		if y_center > slope * x_center + intercept then
			if point.y > slope * point.x + intercept then
				table.insert(new_points, point)
			end
		elseif point.y < slope * point.x + intercept then
			table.insert(new_points, point)
		end
		-- check whether the segment formed by points p and p2 intersects with the line containing
		-- vertexa and vertexb. if so, add the intersection as a new point.
		local point2 = points[p % n_points + 1]
		-- I guess you could find the intersection of the two lines and then check whether the
		-- intersection is on the segment
		local slope2 = (point2.y - point.y) / (point2.x - point.x)
		local intercept2 = point.y - slope2 * point.x
		-- set the two equal to one another...
		-- slope * x + intercept = slope2 * x + intercept2
		-- and solve for x...
		-- slope * x - slope2 * x = intercept2 - intercept
		-- x * (slope - slope2) = intercept2 - intercept
		local x = (intercept2 - intercept) / (slope - slope2)
		if x >= math.min(point.x, point2.x) and x <= math.max(point.x, point2.x) then
			table.insert(new_points, {
				x = x,
				y = slope * x + intercept
			})
		end
	end

	return new_points
end

function calculate_intersection(shape1, shape2)

	-- if shapes are too far apart to intersect, skip calculation
	if shape2.x > shape1.x then
		if shape1.x + shape1.r < shape2.x - shape2.r then
			return
		end
	elseif shape1.x - shape1.r > shape2.x + shape2.r then
		return
	end

	-- start with the assumption that shape2 is entirely inside shape1, then we'll eliminate vertices
	-- as needed (Sutherland-Hodgman clipping algorithm)
	local intersection_points = {}
	for s = 1, shape2.n do
		intersection_points[s] = shape2.vertices[s]
	end

	for side1 = 1, shape1.n do

		local vertex1a = shape1.vertices[side1]
		local vertex1b = shape1.vertices[side1 % shape1.n + 1]
		
		intersection_points = clip_points_to_segment(intersection_points, vertex1a, vertex1b, shape1.x)

		for side2 = 1, shape2.n do
			-- TODO: it's probably a waste of time to do this for every pair of segments...
			-- TODO: trigger unidirectionally? i.e. only when vertex2a ENTERS shape1
			local vertex2a = shape2.vertices[side2]
			local vertex2b = shape2.vertices[side2 % shape2.n + 1]
			local t1, x1, y1 = calculate_point_segment_intersection(vertex2a, vertex1a, vertex1b)
			if t1 ~= nil then
				if t1 > 0 then
					clock.run(function()
						clock.sleep(t1 * rate)
						shape1:on_side_struck(side1)
					end)
				else
					shape1:on_side_struck(side1)
				end
				shape1.side_levels[side1] = 1
				vertex2a.level = 1
			end
			local t2, x2, y2 = calculate_point_segment_intersection(vertex1a, vertex2a, vertex2b)
			if t2 ~= nil then
				if t2 > 0 then
					clock.run(function()
						clock.sleep(t2 * rate)
						shape2:on_side_struck(side2)
					end)
				else
					shape2:on_side_struck(side2)
				end
				shape2.side_levels[side2] = 1
				vertex1a.level = 1
			end
		end
	end
			
	-- calculate intersection area
	local area = 0
	local overlap = 0
	if intersection_points[1] ~= nil then
		local n_points = #intersection_points
		screen.move(intersection_points[1].x, intersection_points[1].y)
		for p = 1, n_points do
			local point = intersection_points[p]
			screen.line(point.x, point.y)
			local point2 = intersection_points[p % n_points + 1]
			area = area + point.x * point2.y - point.y * point2.x
		end
		overlap = area / math.min(shape1.area, shape2.area)
	end
	crow.output[1].volts = 10 * overlap
	engine.pw(overlap)
end

shapes = {}
n_shapes = 0
rate = 1 / 32

shape_matrix = {}

function init()

	shapes[1] = Shape.new(3, 30, 70, tau / 200)
	shapes[1].notes = { 28, 40, 47 }
	shapes[1].on_side_struck = function(self, side)
		-- crow.ii.tt.script(2)
		engine.hz(musicutil.note_num_to_freq(self.notes[side]))
	end

	shapes[2] = Shape.new(5, 30, 55, tau / 300)
	shapes[2].notes = { 52, 55, 59, 60, 62 }
	shapes[2].on_side_struck = function(self, side)
		-- crow.ii.tt.script(4)
		engine.hz(musicutil.note_num_to_freq(self.notes[side]))
	end

	n_shapes = 2
	
	local m = 1
	for s1 = 1, n_shapes do
		for s2 = s1 + 1, n_shapes do
			shape_matrix[m] = {
				note = 1, -- TODO
				intersection = 0
			}
		end
	end

	clock.run(function()
		while true do
			clock.sync(rate)
			for s = 1, n_shapes do
				local shape = shapes[s]
				for v = 1, shape.n do
					shape.side_levels[v] = shape.side_levels[v] * 0.85
					shape.vertices[v].level = shape.vertices[v].level * 0.85
				end
				shape:rotate()
			end
			redraw()
		end
	end)
	
	crow.output[2].action = '{ to(5, 0), to(0, 0.1) }'
	crow.output[4].action = '{ to(5, 0), to(0, 0.1) }'
end

function redraw()
	screen.clear()
	screen.aa(1)
	for s1 = 1, n_shapes do
		local shape1 = shapes[s1]
		for s2 = s1 + 1, #shapes do
			local shape2 = shapes[s2]
			calculate_intersection(shape1, shape2)
		end
	end
	for s = 1, n_shapes do
		shapes[s]:draw_lines()
	end
	for s = 1, n_shapes do
		shapes[s]:draw_points()
	end
	screen.update()
end

shift = false

function key(n, z)
	if n == 2 then
		shift = z == 1
	end
end

function enc(n, d)
	if n == 2 then
		if shift then
			shapes[1].rate = shapes[1].rate + d * 0.001
		else
			shapes[1].x = shapes[1].x + d
		end
	elseif n == 3 then
		shapes[1].r = shapes[1].r + d
		shapes[1]:calculate_area()
	end
end