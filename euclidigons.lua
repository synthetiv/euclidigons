-- euclidigons
--
-- spinning shapes. where they
-- collide, notes are produced.
--
-- E1: select polygon
-- E2: move selected polygon
-- E3: resize selected polygon
-- tap K3: mute/unmute
--          selected polygon
--
-- K2 + E2: set rotation speed
-- K2 + E3: set # of sides
-- K2 + tap K3: add new polygon
--
-- K3 + E2: choose new note
-- K3 + E3: choose new octave
--           OR in midi mode,
--           choose device/ch.
-- (changes to note/oct/dev/ch.
-- apply when K3 is released)
-- K3 + hold K1: undo change
--                to note/oct/
--                device/channel
-- K3 + tap K2: delete selected
--               polygon

engine.name = 'PrimitiveString'
num_voices = 19
musicutil = require 'musicutil'

Voice = require 'voice'
voice_manager = Voice.new(num_voices, Voice.MODE_LRU)
function voice_remove(self)
	-- find and remove self from shape's voice table
	local shape_voices = self.shape.voices
	local found = false
	for v = 1, #shape_voices do
		if shape_voices[v] == self then
			found = true
		end
		if found then
			shape_voices[v] = shape_voices[v + 1]
		end
	end
end
function voice_release(self)
	engine.gate(self.id, 0)
	voice_remove(self)
end
for v = 1, num_voices do
	voice_manager.style.slots[v].on_release = voice_release
	voice_manager.style.slots[v].on_steal = voice_remove
end

ShapeParamGroup = include 'lib/shape_param_group'
Shape = include 'lib/shape'
midi_out = include 'lib/midi'

tau = math.pi * 2
y_center = 32.5

edit_shape = nil
num_shapes = 9
shape_param_groups = {}
shapes = {} -- sorted by position, size, id

rate = 1 / 48

scale = musicutil.generate_scale(36, 'minor pentatonic', 1)

held_keys = { false, false, false }
k3_time = 0

s_IN = 1
s_OUT = 2
s_BOTH = 3
trigger_style = s_IN

m_BOTH = 1
m_NOTE = 2
mute_style = m_BOTH

o_ENGINE = 1
o_MIDI = 2
o_BOTH = 3
output_mode = o_ENGINE

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

--- remove a shape
-- @param shape a Shape table, or nil to delete the currently selected shape
function delete_shape(shape)
	shape = shape or edit_shape
	local is_edit_shape = shape == edit_shape
	local found = false
	-- remove shape from shapes table, and remove references from other shapes' voices tables
	for s = 1, #shapes do
		if shapes[s] == shape then
			found = true
		end
		if found then
			shapes[s] = shapes[s + 1]
		end
		if shapes[s] then -- this will be nil for the final value of `s`
			local other_id = shapes[s].id
			local other_voices = shapes[s].voices
			-- release voices played by shape
			for v, voice in ipairs(other_voices) do
				if voice.other == shape then
					voice:release()
				end
			end
		end
	end
	-- free voices and params
	shape:free()
	if is_edit_shape then
		-- select another shape
		if #shapes > 0 then
			edit_shape = get_next_shape(-1) or shapes[1]
		else
			edit_shape = nil
		end
	end
end

function get_unused_param_group()
	for i = 1, num_shapes do
		if shape_param_groups[i].shape == nil then
			return shape_param_groups[i]
		end
	end
end

function insert_shape()
	-- bail if we're out of shapes
	if #shapes >= 9 then
		return
	end
	-- take on attributes of current shape, if any
	local note = 1
	local output_mode = o_ENGINE
	local midi_device = 1
	local midi_channel = 1
	if edit_shape then
		tab.print(edit_shape)
		note = edit_shape.note - 4
		output_mode = edit_shape.output_mode
		midi_device = edit_shape.midi_device
		midi_channel = edit_shape.midi_channel
	end
	-- randomize a few attributes
	local radius = math.random(13, 30)
	local rate = math.random()
	rate = rate * (math.random(2) - 1.5) * 2 -- randomize sign
	-- get the next unused param group and populate it
	local group = get_unused_param_group() -- should never be nil; if it is, we have bigger problems
	edit_shape = Shape.new(group)
	group.note = note
	group.n = math.random(3, 9)
	group.r = radius
	group.x = math.random(radius, 128 - radius) + 0.5
	group.rate = rate
	-- create a shape
	-- add to main shapes table
	table.insert(shapes, edit_shape)
end

function handle_strike(shape, side, pos, vel, x, y, other, vertex)
	-- scale/curve velocity to [0, 1]
	local vel_scaled = math.pow(math.abs(vel / 16), 1.5)
	vel_scaled = vel_scaled / (1 + vel_scaled)
	local output_mode = output_mode or shape.output_mode
	if output_mode == o_ENGINE or output_mode == o_BOTH then
		local voice = voice_manager:get()
		voice.shape = shape
		voice.side = side
		voice.other = other
		voice.vertex = vertex
		engine.hz(voice.id, shape.note_freq)
		engine.pos(voice.id, pos)
		engine.pan(voice.id, (x / 64) - 1)
		engine.vel(voice.id, vel_scaled)
		engine.trig(voice.id)
		table.insert(shape.voices, voice)
	end
	if output_mode == o_MIDI or output_mode == o_BOTH then
		midi_out:trigger(shape, math.floor(vel_scaled * 127 + 0.5))
	end
end

function init()
	
	norns.enc.sens(1, 4) -- shape selection
	norns.enc.accel(1, false)

	local scale_names = {}
	for i = 1, #musicutil.SCALES do
		table.insert(scale_names, string.lower(musicutil.SCALES[i].name))
	end
	
	midi_out:connect()

	params:add_separator('behavior')

	params:add{
		id = 'trigger_style',
		name = 'trigger style',
		type = 'option',
		options = { 'in only', 'out only', 'in/out' },
		default = trigger_style,
		action = function(value)
			trigger_style = value
		end
	}

	params:add{
		id = 'mute_style',
		name = 'mute style',
		type = 'option',
		options = { 'absolute', 'own note only' },
		default = mute_style,
		action = function(value)
			mute_style = value
		end
	}
	
	params:add{
		id = 'output',
		name = 'output',
		type = 'option',
		options = { 'internal', 'midi', 'both', 'multi (per shape)' },
		default = output_mode,
		action = function(value)
			if value == 4 then
				output_mode = nil
			else
				output_mode = value
			end
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
		action = function(value)
			engine.amp(value)
		end
	}

	params:add{
		id = 'wave',
		name = 'wave (pulse/saw)',
		type = 'control',
		controlspec = controlspec.new(0, 1, 'lin', 0, 0.5),
		action = function(value)
			engine.wave(value)
		end
	}

	params:add{
		id = 'noise',
		name = 'pulse noise',
		type = 'control',
		controlspec = controlspec.new(0.01, 10, 'exp', 0, 0.25),
		action = function(value)
			engine.noise(value)
		end
	}

	params:add{
		id = 'comb',
		name = 'saw comb',
		type = 'control',
		controlspec = controlspec.new(0.1, 5, 'exp', 0, 0.2),
		action = function(value)
			engine.comb(value)
		end
	}

	params:add{
		id = 'brightness',
		name = 'brightness',
		type = 'control',
		controlspec = controlspec.new(0.01, 2, 'exp', 0, 0.7),
		action = function(value)
			engine.brightness(value)
		end
	}

	params:add{
		type = 'control',
		id = 'attack',
		name = 'attack',
		controlspec = controlspec.new(0.005, 3, 'exp', 0, 0.005, 's'),
		action = function(value)
			engine.attack(value)
		end
	}

	params:add{
		type = 'control',
		id = 'release',
		name = 'release',
		controlspec = controlspec.new(0.01, 7, 'exp', 0, 0.39, 's'),
		action = function(value)
			engine.release(value)
		end
	}

	params:add_separator('midi')
	
	params:add{
		type = 'number',
		id = 'midi_device',
		name = 'midi device',
		min = 1,
		max = 5,
		default = midi_out.device,
		formatter = function(param)
			local value = param:get()
			if value == 5 then
				return 'multi (per shape)'
			else
				return midi_out.devices[value].name -- TODO: why is crow showing up here?!
			end
		end,
		action = function(value)
			if value == 5 then
				midi_out.device = nil
			else
				midi_out.device = value
			end
		end
	}

	params:add{
		type = 'number',
		id = 'midi_channel',
		name = 'midi channel',
		min = 1,
		max = 17,
		default = midi_out.channel,
		formatter = function(param)
			local value = param:get()
			if value == 17 then
				return 'multi (per shape)'
			else
				return value
			end
		end,
		action = function(value)
			if value == 17 then
				midi_out.channel = nil
			else
				midi_out.channel = value
			end
		end
	}

	params:add{
		type = 'control',
		id = 'midi_trigger_length',
		name = 'note length',
		controlspec = controlspec.new(0.01, 3, 'exp', 0, 0.05, 's'),
		action = function(value)
			midi_out.trigger_length = value
		end
	}
	
	params:add{
		type = 'trigger',
		id = 'midi_clear',
		name = 'clear midi notes',
		action = function()
			midi_out:clear_async()
		end
	}

	params:add_separator('shapes')

	for n = 1, num_shapes do
		shape_param_groups[n] = ShapeParamGroup.new(n)
	end

	-- TODO: add a trigger to reindex shape params (make param groups match screen order)
	params:add{
		type = 'trigger',
		id = 'renumber_shapes',
		name = 'renumber shapes',
		action = function()
			for n = 1, num_shapes do
				shape_param_groups[n].shape = nil
			end
			for n = 1, #shapes do
				shape_param_groups[n].shape = shapes[n]
				shapes[n].params = shape_param_groups[n]
				shapes[n]:update_params()
			end
		end
	}

	for s = 1, 2 do
		insert_shape()
		edit_shape.params.active = 1
	end

	params:bang()

	clock.run(function()
		while true do
			clock.sync(rate / clock.get_beat_sec())
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

function draw_undo()
	if edit_shape.edits.dirty then
		screen.font_face(2)
		screen.level(5)
		screen.move(0, 10)
		if edit_shape.edits.compare then
			screen.text('hold K1: redo')
		else
			screen.text('hold K1: undo')
			screen.move(128, 64)
			screen.text_right('release K3: OK')
		end
	end
end

function redraw()
	screen.clear()
	screen.aa(1)
	screen.font_face(1)
	local dim = held_keys[3] and output_mode ~= o_ENGINE
	for s = 1, #shapes do
		if shapes[s] ~= edit_shape then
			shapes[s]:draw_lines(false, dim)
		end
	end
	if edit_shape ~= nil then
		edit_shape:draw_lines(true, dim)
	end
	for s = 1, #shapes do
		if shapes[s] ~= edit_shape then
			shapes[s]:draw_points(false, dim)
		end
	end
	if edit_shape ~= nil then
		edit_shape:draw_points(true, dim)
		if held_keys[2] or (held_keys[3] and output_mode == o_ENGINE) then
			if held_keys[2] then
				draw_setting_centered(edit_shape.x, edit_shape.n)
			elseif held_keys[3] then
				draw_setting_centered(edit_shape.x, edit_shape.edits.note_name)
				draw_undo()
			end
		elseif held_keys[3] then
			draw_undo()
			screen.font_face(2)
			local mode = (output_mode or edit_shape.edits.output_mode)
			local device = (midi_out.device or edit_shape.edits.midi_device)
			local y = 10
			if output_mode == nil or midi_out.device == nil then
				if mode == o_ENGINE then
					device = 'internal'
				elseif mode == o_BOTH then
					device = 'int + ' .. midi_out.devices[device].name
				else
					device = midi_out.devices[device].name
				end
				draw_setting(y, 'out:', device)
				y = y + 10
			end
			if midi_out.channel == nil then
				local channel = (midi_out.channel or edit_shape.edits.midi_channel)
				if mode == o_ENGINE then
					channel = '-'
				end
				draw_setting(y, 'channel:', channel)
				y = y + 10
			end
			draw_setting(y, 'note:', string.format('%s (%s)', edit_shape.edits.midi_note, edit_shape.edits.note_name))
		end
	end
	screen.update()
end

function draw_setting(y, label, value)
	local width = screen.text_extents(label .. value) + 3
	screen.move(128 - width, y)
	screen.level(3)
	screen.text(label)
	screen.move_rel(3, 0)
	screen.level(10)
	screen.text(value)
end

function draw_setting_centered(x, value)
	local w, h = screen.text_extents(value)
	local x = util.clamp(x - w / 2, 0, 128 - w)
	screen.rect(x - 1, y_center - 1 - h / 2, w + 2, h + 2)
	screen.level(0)
	screen.fill()
	screen.move(x, y_center + h / 2)
	screen.level(15)
	screen.text(value)
end

function key(n, z)

	held_keys[n] = z == 1

	if n == 1 then
		if z == 1 then
			if held_keys[3] then
				k3_time = 0
				if edit_shape ~= nil and edit_shape.edits.dirty then
					edit_shape.edits:undo()
				end
			end
		end
	elseif n == 2 then
		if z == 1 then
			if held_keys[3] then
				k3_time = 0
				delete_shape()
			end
		end
	elseif n == 3 then
		local now = util.time()
		if z == 1 then
			if held_keys[2] then
				insert_shape()
			else
				k3_time = now
			end
		else
			if edit_shape ~= nil then
				if edit_shape.edits.dirty then
					edit_shape.edits:apply()
				elseif k3_time > now - 0.25 then
					edit_shape.params.active = 1 - edit_shape.params.active
				end
			end
		end
	end

	if held_keys[3] then
		norns.enc.sens(2, 4) -- note
		norns.enc.accel(2, false)
		norns.enc.sens(3, 4) -- octave
		norns.enc.accel(3, false)
	elseif held_keys[2] then
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
			if held_keys[2] then
				-- set rotation rate
				edit_shape.params:delta('rate', d)
			elseif held_keys[3] then
				-- set note
				edit_shape.edits.note = edit_shape.edits.note + d
			else
				-- set position
				edit_shape.params:delta('x', d)
			end
		end
	elseif n == 3 then
		if edit_shape ~= nil then
			if held_keys[2] then
				-- set number of sides
				edit_shape.params:delta('n', d)
			elseif held_keys[3] then
				k3_time = 0
				if output_mode == o_ENGINE or (output_mode ~= nil and midi_out.device ~= nil and midi_out.channel ~= nil) then
					-- device and channel are either fixed or irrelevant; set octave
					edit_shape.edits.note = edit_shape.edits.note + d * #scale
				else
					local edits = edit_shape.edits
					local next_mode = edits.output_mode + d
					local can_change_mode = output_mode == nil and (next_mode >= 1 and next_mode <= 2)
					local next_device = edits.midi_device + d
					local can_change_device = midi_out.device == nil and (output_mode ~= nil or edits.output_mode ~= o_ENGINE) and (next_device >= 1 and next_device <= 4)
					local next_channel = edits.midi_channel + d
					local can_change_channel = midi_out.channel == nil and (output_mode ~= nil or edits.output_mode ~= o_ENGINE) and (next_channel >= 1 and next_channel <= 16)
					if can_change_channel then
						edits.midi_channel = (next_channel - 1) % 16 + 1
					elseif can_change_device then
						edits.midi_device = (next_device - 1) % 4 + 1
						edits.midi_channel = d > 0 and 1 or 16
					elseif can_change_mode then
						edits.output_mode = next_mode
						edits.midi_channel = d > 0 and 1 or 16
						edits.midi_device = d > 0 and 1 or 4
					end
				end
			else
				-- set size
				edit_shape.params:delta('r', d)
			end
		end
	end
end

function cleanup()
	midi_out:clear_sync()
end