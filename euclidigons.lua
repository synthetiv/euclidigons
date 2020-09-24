-- euclidigons
--
-- spinning shapes. where they collide, notes are produced.
--
-- E1 = select polygon
-- E2 = move selected polygon
-- E3 = resize selected polygon
-- K3 = mute/unmute selected polygon
--
-- K2 + E2 = set rotation speed
-- K2 + E3 = set number of sides
--
-- K1 + E2 = set note
-- K1 + E3 = set octave
--
-- K1 + K2 = delete selected polygon
-- K1 + K3 = add new polygon

engine.name = 'PolyPerc'
musicutil = require 'musicutil'

local Shape = include 'lib/shape'

tau = math.pi * 2
y_center = 32.5

edit_shape = nil
shapes = {}

rate = 1 / 32
tick_notes = 0
max_tick_notes = 16

scale = musicutil.generate_scale(36, 'minor pentatonic', 1)

alt = false
shift = false

s_IN_OUT = 1
s_IN = 2
s_OUT = 3
trigger_style = s_IN_OUT

--- sorting callback for Shapes
-- @param a shape A
-- @param b shape B
-- @return true if shape A should be ordered first, based on criteria: position, size, and which
--         shape was created first
function compare_shapes(a, b)
	if a.x == b.x then
		if a.r == b.r then
			return a.id < b.id
		end
		return a.r < b.r
	end
	return a.x < b.x
end

--- find the 'next' shape before or after `edit_shape`, ordering shapes as described above
-- @param direction 1 or -1
-- @return a Shape, or nil if `edit_shape` is the first or last shape
function get_next_shape(direction)
	table.sort(shapes, compare_shapes)
	local found = false
	if direction > 0 then
		for s = 1, #shapes do
			if shapes[s] ~= edit_shape and not compare_shapes(shapes[s], edit_shape) then
				return shapes[s]
			end
		end
	else
		for s = #shapes, 1, -1 do
			if shapes[s] ~= edit_shape and compare_shapes(shapes[s], edit_shape) then
				return shapes[s]
			end
		end
	end
end

function delete_shape()
	local found = false
	for s = 1, #shapes do
		if shapes[s] == edit_shape then
			found = true
		end
		if found then
			shapes[s] = shapes[s + 1]
		end
	end
	if #shapes > 0 then
		edit_shape = get_next_shape(-1) or shapes[1]
	else
		edit_shape = nil
	end
end

function insert_shape()
	local note = 1
	if edit_shape then
		note = edit_shape.note + 2
	end
	local radius = math.random(13, 30)
	local rate = math.random() * 15 + 10
	rate = tau / (rate * rate)
	edit_shape = Shape.new(note, math.random(3, 9), radius, math.random(radius, 128 - radius) + 0.5, rate)
	table.insert(shapes, edit_shape)
end

function handle_strike(shape, side, pos)
	if tick_notes < max_tick_notes then
		engine.hz(shape.note_freq)
		tick_notes = tick_notes + 1
	end
end

function init()

	norns.enc.sens(1, 4) -- shape selection
	norns.enc.accel(1, false)

	for s = 1, 2 do
		insert_shape()
		edit_shape.mute = false
	end

	local scale_names = {}
  for i = 1, #musicutil.SCALES do
    table.insert(scale_names, string.lower(musicutil.SCALES[i].name))
  end

  params:add_separator('behavior')

  params:add{
		id = 'trigger_style',
		name = 'trigger style',
		type = 'option',
		options = { 'in/out', 'in only', 'out only' },
		default = 2,
		action = function(value)
			trigger_style = value
		end
	}

  params:add_separator('scale')

  params:add{
		id = 'scale_mode',
		name = 'scale mode',
		type = 'option',
		options = scale_names,
		default = 5,
		action = function(value)
			scale = musicutil.generate_scale(params:get('root_note'), value, 1)
			for s = 1, #shapes do
				shapes[s].note = shapes[s].note
			end
		end
	}

  params:add{
		id = 'root_note',
		name = 'root note',
		type = 'number',
		min = 0,
		max = 127,
		default = 60,
		formatter = function(param)
			return musicutil.note_num_to_name(param:get(), true)
		end,
		action = function(value)
			scale = musicutil.generate_scale(value, params:get('scale_mode'), 1)
			for s = 1, #shapes do
				shapes[s].note = shapes[s].note
			end
		end
	}

  params:add_separator('timbre')

  params:add{
		id = 'amp',
		name = 'amp',
		type = 'control',
		controlspec = controlspec.new(0, 1, 'lin', 0, 0.5),
		action = function(x)
			engine.amp(x)
		end
	}

  params:add{
		id = 'pw',
		name = 'pulsewidth',
		type = 'control',
		controlspec = controlspec.new(0, 100, 'lin', 0, 47, '%'),
		action = function(value)
			engine.pw(value * 0.01)
		end
	}

  params:add{
		type = 'control',
		id = 'release',
		controlspec = controlspec.new(0.1, 3.2, 'lin', 0, 0.39, 's'),
		action = function(x)
			engine.release(x)
		end
	}

  params:add{
		id = 'cutoff',
		name = 'filter cutoff',
		type = 'control',
		controlspec = controlspec.new(50, 10000, 'exp', 0, 3300, 'hz'),
		action = function(value)
			engine.cutoff(value)
		end
	}

  params:add{
		id = 'gain',
		name = 'filter gain',
		type = 'control',
		controlspec = controlspec.new(0, 4, 'lin', 0, 0.6),
		action = function(value)
			engine.gain(value)
		end
	}

	params:bang()

	clock.run(function()
		while true do
			tick_notes = 0
			clock.sync(rate)
			for s = 1, #shapes do
				local shape = shapes[s]
				for v = 1, shape.n do
					-- decay level fades
					shape.side_levels[v] = shape.side_levels[v] * 0.85
					shape.vertices[v].level = shape.vertices[v].level * 0.85
				end
				-- calculate position in next frame
				shape:tick()
			end
			-- check for intersections between shapes between now and the next frame, play notes as needed
			for s1 = 1, #shapes do
				local shape1 = shapes[s1]
				for s2 = 1, #shapes do
					if s1 ~= s2 then
						shapes[s1]:check_intersection(shapes[s2])
					end
				end
			end
			redraw()
		end
	end)
end

function redraw()
	screen.clear()
	screen.aa(1)
	for s = 1, #shapes do
		if shapes[s] ~= edit_shape then
			shapes[s]:draw_lines()
		end
	end
	if edit_shape ~= nil then
		edit_shape:draw_lines(true)
	end
	for s = 1, #shapes do
		if shapes[s] ~= edit_shape then
			shapes[s]:draw_points()
		end
	end
	if edit_shape ~= nil then
		edit_shape:draw_points(true)
		if shift or alt then
			local label = ''
			if shift then
				label = edit_shape.n
			elseif alt then
				label = edit_shape.note_name
			end
			local label_w, label_h = screen.text_extents(label)
			local label_x = util.clamp(edit_shape.x - label_w / 2, 0, 128 - label_w)
			screen.rect(label_x - 1, y_center - 1 - label_h / 2, label_w + 2, label_h + 2)
			screen.level(0)
			screen.fill()
			screen.move(label_x, y_center + label_h / 2)
			screen.level(15)
			screen.text(label)
		end
	end
	screen.update()
end

function key(n, z)
	if n == 1 then
		alt = z == 1
	elseif n == 2 then
		if alt then
			if z == 1 then
				delete_shape()
			else
				shift = false
			end
		else
			shift = z == 1
		end
	elseif n == 3 then
		if z == 1 then
			if alt then
				insert_shape()
			elseif edit_shape ~= nil then
				edit_shape.mute = not edit_shape.mute
			end
		end
	end
	if alt then
		norns.enc.sens(2, 4) -- note
		norns.enc.accel(2, false)
		norns.enc.sens(3, 4) -- octave
		norns.enc.accel(3, false)
	elseif shift then
		norns.enc.sens(2, 1) -- speed
		norns.enc.accel(2, true)
		norns.enc.sens(3, 4) -- # of sides
		norns.enc.accel(3, false)
	else
		norns.enc.sens(2, 1) -- position
		norns.enc.accel(2, true)
		norns.enc.sens(3, 1) -- size
		norns.enc.accel(3, false)
	end
end

function enc(n, d)
	if n == 1 then
		-- select shape to edit
		edit_shape = get_next_shape(d) or edit_shape
	elseif n == 2 then
		if edit_shape ~= nil then
			if shift then
				-- set rotation rate
				edit_shape.rate = edit_shape.rate + d * 0.0015
			elseif alt then
				-- set note
				edit_shape.note = edit_shape.note + d
			else
				-- set position
				edit_shape.delta_x = edit_shape.delta_x + d
			end
		end
	elseif n == 3 then
		if edit_shape ~= nil then
			if shift then
				-- set number of sides
				edit_shape.n = util.clamp(edit_shape.n + d, 1, 9)
			elseif alt then
				-- set octave
				edit_shape.note = edit_shape.note + d * #scale
			else
				-- set size
				edit_shape.r = math.max(edit_shape.r + d, 1)
			end
		end
	end
end