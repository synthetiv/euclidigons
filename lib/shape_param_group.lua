--- ShapeParamGroup class
-- @classmod shape_param_group

local ShapeParamGroup = {}

ShapeParamGroup.param_ids = {
	'note',
	'output_mode',
	'midi_device',
	'midi_channel',
	'active',
	'n',
	'r',
	'x',
	'theta',
	'rate',
	'in_use'
}

--- constructor
-- @tparam int index group number
function ShapeParamGroup.new(index)

	local prefix = string.format('shape_%d_', index)

	local group = {
		index = index,
		params = {}
	}

	params:add_group('shape ' .. index, 10)

	params:add{
		type = 'number',
		id = prefix .. 'note',
		name = 'note',
		min = -126, -- TODO: make sure this range is sensible
		max = 128,
		default = 1,
		action = function(value)
			if group.shape ~= nil then
				group.shape.note = value -- TODO: clamp here instead of in get_note_values()
				group.shape.midi_note, group.shape.note_name, group.shape.note_freq = group.shape:get_note_values(value)
			end
		end,
		formatter = function(param)
			-- TODO: make sure this really works and responds correctly to changes in scale
			-- TODO: show MIDI note number in MIDI mode...?
			if group.shape ~= nil then
				return group.shape.note_name
			else
				return '--'
			end
		end
	}

	-- TODO: show/hide based on global setting
	params:add{
		type = 'option',
		id = prefix .. 'output_mode',
		name = 'output mode',
		options = { 'engine', 'midi', 'both' },
		default = 1,
		action = function(value)
			if group.shape ~= nil then
				group.shape.active = value == 1 -- TODO: fix this!!
			end
		end
	}

	-- TODO: show/hide
	params:add{
		type = 'number',
		id = prefix .. 'midi_device',
		name = 'midi device',
		min = 1,
		max = 4,
		default = 1,
		action = function(value)
			if group.shape ~= nil then
				group.shape.midi_device = value
			end
		end,
		formatter = function(param)
			value = param:get()
			return midi_out.devices[value].name
		end
	}

	-- TODO: show/hide
	params:add{
		type = 'number',
		id = prefix .. 'midi_channel',
		name = 'midi channel',
		min = 1,
		max = 16,
		default = 1,
		action = function(value)
			if group.shape ~= nil then
				group.shape.midi_channel = value
			end
		end
	}

	params:add{
		type = 'number',
		id = prefix .. 'active',
		name = 'active',
		min = 0,
		max = 1,
		default = 0,
		action = function(value)
			if group.shape ~= nil then
				group.shape.active = (value == 1)
			end
		end,
		formatter = function(param)
			value = param:get()
			return (value == 1) and 'on' or 'off'
		end
	}

	params:add{
		type = 'number',
		id = prefix .. 'n',
		name = 'sides',
		min = 1,
		max = 9,
		default = 3,
		action = function(value)
			if group.shape ~= nil then
				group.shape.n = value
				group.shape:calculate_points()
				group.shape:calculate_area()
			end
		end
	}

	params:add{
		type = 'control',
		id = prefix .. 'r',
		name = 'radius',
		controlspec = controlspec.new(1, 128, 'lin', 0, 16, '', 0.01),
		action = function(value)
			if group.shape ~= nil then
				group.shape.r = value
				group.shape:calculate_area()
			end
		end
	}

	params:add{
		type = 'control',
		id = prefix .. 'x',
		name = 'x',
		controlspec = controlspec.new(-128, 256, 'lin', 0, 64, '', 0.002),
		action = function(value)
			if group.shape ~= nil then
				group.shape.nx = value
			end
		end
	}

	params:add{
		type = 'control',
		id = prefix .. 'rate',
		name = 'rate',
		-- TODO: vary with tempo: rotations per beat (this is currently rotations per 1/4 second)
		-- TODO: bipolar exponential warp?
		-- TODO: vary min/max with number of sides...? (two-sided shape can't spin very fast)
		controlspec = controlspec.new(-4, 4, 'lin', 0, 0, '', 0.0005),
		action = function(value)
			if group.shape ~= nil then
				group.shape.rate = value * tau * rate
			end
		end
	}
	
	params:add{
		type = 'control',
		id = prefix .. 'theta',
		name = 'angle',
		controlspec = controlspec.new(0, tau, 'lin', 0, 0, '', 0.01, true),
		action = function(value)
			if group.shape ~= nil then
				group.shape.theta = value
			end
		end,
		formatter = function(param)
			local value = param:get()
			return string.format('%d°', util.round(value * 360 / tau))
		end,
	}

	-- 'in use' is a hidden param that causes shapes to be created/destroyed as
	-- needed when restoring a pset
	params:add{
		type = 'number',
		id = prefix .. 'in_use',
		name = 'in use',
		min = 0,
		max = 1,
		default = 0,
		action = function(value)
			print('in use?', value)
			if group.shape == nil and value == 1 then
				group.shape = Shape.new(group)
				print('insert shape')
				table.insert(shapes, group.shape)
				edit_shape = group.shape
			elseif group.shape ~= nil and value == 0 then
				print('delete shape')
				delete_shape(group.shape)
			end
		end
	}
	params:hide(prefix .. 'in_use')

	for i, id in ipairs(ShapeParamGroup.param_ids) do
		group.params[id] = params:lookup_param(prefix .. id)
	end

	return setmetatable(group, ShapeParamGroup)
end

--- make `group.x = 10` syntactic sugar for `params:set('shape_#_x', 10)`
-- @tparam string index usually a param name, or 'shape' to connect to a Shape table
-- @tparam mixed value new value
function ShapeParamGroup:__newindex(index, value)
	-- allow `shape` field to be set directly
	if index == 'shape' then
		rawset(self, index, value)
	end
	-- otherwise, forward to params
	if self.params[index] ~= nil then
		self.params[index]:set(value)
	end
end

--- make `group.x` syntactic sugar for `params:get('shape_#_x')`
-- @tparam string index param name
function ShapeParamGroup:__index(index)
	if self.params[index] ~= nil then
		return self.params[index]:get()
	end
	return ShapeParamGroup[index]
end

--- increment/decrement a parameter
-- @tparam string index param name
-- @tparam int d delta
function ShapeParamGroup:delta(index, d)
	if self.params[index] ~= nil then
		self.params[index]:delta(d)
	end
end

--- update shape by banging all params
function ShapeParamGroup:update_shape()
	for i, id in ipairs(ShapeParamGroup.param_ids) do
		if id ~= 'in_use' then
			self.params[id]:bang()
		end
	end
end

return ShapeParamGroup