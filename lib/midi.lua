local midi_out = {}

midi_out.devices = {}
midi_out.device = 1
midi_out.channel = 1

midi_out.active_notes = {}
for d = 1, 4 do
	local channels = {}
	for c = 1, 16 do
		notes = {}
		for n = 0, 127 do
			notes[n] = 0
		end
		channels[c] = notes
	end
	midi_out.active_notes[d] = channels
end

function midi_out:trigger(shape, vel)
	local device = self.device or shape.midi_device
	local channel = self.channel or shape.midi_channel
	local note = shape.midi_note
	local length = self.trigger_length
	local active_notes = self.active_notes[device][channel]
	midi.vports[device]:note_on(note, vel, channel)
	active_notes[note] = active_notes[note] + 1
	clock.run(function()
		clock.sleep(length)
		active_notes[note] = active_notes[note] - 1
		-- if active_notes[note] < 1 then
			midi.vports[device]:note_off(note, 0, channel)
		-- end
	end)
end

function midi_out:connect()
	for d = 1, 4 do
		self.devices[d] = midi.connect(d)
	end
end

-- clear all notes on all devices, right now
function midi_out:clear_sync()
	for d = 1, 4 do
		for c = 1, 16 do
			for n = 0, 127 do
				midi_out.devices[d]:note_off(n, 0, c)
			end
		end
	end
end

-- clear all notes on all devices, with throttling
function midi_out:clear_async()
	clock.run(function()
		for d = 1, 4 do
			for c = 1, 16 do
				for n = 0, 127 do
					midi_out.devices[d]:note_off(n, 0, c)
					if n % 64 == 0 then
						clock.sleep(0.01)
					end
				end
			end
		end
	end)
end

return midi_out