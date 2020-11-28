local ShapeEditBuffer = {}

function ShapeEditBuffer.new()
	local buffer = {
		values = {},
		dirty = false,
		compare = false
	}
	return setmetatable(buffer, ShapeEditBuffer)
end

function ShapeEditBuffer:__index(index)
	if self.compare then
		return ShapeEditBuffer[index] or edit_shape[index]
	end
	return self.values[index] or ShapeEditBuffer[index] or edit_shape[index]
end

function ShapeEditBuffer:__newindex(index, value)
	if self.compare then
		self:reset()
	end
	self.values[index] = value
	if index == 'note' then
		self.values.midi_note, self.values.note_name, self.values.note_freq = edit_shape:get_note_values(value)
	end
	self.dirty = true
end

function ShapeEditBuffer:apply()
	if not self.compare then
		edit_shape.note = self.note
		edit_shape.output_mode = self.output_mode
		edit_shape.midi_device = self.midi_device
		edit_shape.midi_channel = self.midi_channel
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

return ShapeEditBuffer