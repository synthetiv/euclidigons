Shape = {}

function Shape.new(note, n, r, x, rate)
	local shape = {
		_note = 1,
		note_freq = 440,
		_n = 0,
		area = 0,
		r = r,
		x = x,
		rate = rate,
		theta = 0,
		vertices = {},
		side_levels = {}
	}
	setmetatable(shape, Shape)
	-- initialize with 'n' sides and note 'note'
	shape.n = n
	shape.note = note
	return shape
end

function Shape:__newindex(index, value)
	if index == 'n' then
		self._n = value
		self:calculate_points()
		self:calculate_area()
	elseif index == 'note' then
		self._note = value
		local scale_degrees = #scale
		local degree = (value - 1) % #scale + 1
		local octave = math.floor(self.note / #scale)
		self.note_freq = musicutil.note_num_to_freq(scale[degree] + octave * 12)
	end
end

function Shape:__index(index)
	if index == 'n' then
		return self._n
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
		local nx = self.x + math.cos(self.theta + v * vertex_angle) * self.r
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

function Shape:rotate()
	self.theta = self.theta + self.rate
	while self.theta > tau do
		self.theta = self.theta - tau
	end
	self:calculate_points()
end

function Shape:draw_lines(selected)
	for v = 1, self.n do
		local vertex1 = self.vertices[v]
		local vertex2 = self.vertices[v % self.n + 1]
		local level = self.side_levels[v]
		if selected then
			level = level * 0.7 + 0.3
		end
		screen.move(vertex1.x, vertex1.y)
		screen.line(vertex2.x, vertex2.y)
		screen.level(math.floor(2 + level * 13))
		screen.line_width(math.floor(1 + level))
		screen.stroke()
	end
end
	
function Shape:draw_points(selected)
	for v = 1, self.n do
		local vertex = self.vertices[v]
		local level = vertex.level
		if selected then
			level = level * 0.8 + 0.2
		end
		screen.circle(vertex.x, vertex.y, 0.5 + level * 3)
		screen.level(math.floor(6 + level * 9))
		screen.fill()
	end
end

function Shape:on_strike(side)
	-- crow.ii.tt.script(2)
	engine.hz(self.note_freq)
end

return Shape