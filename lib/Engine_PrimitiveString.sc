Engine_PrimitiveString : CroneEngine {
	var controlBus;
	var voices;
	
	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		
		controlBus = Dictionary.new;
		controlBus.add(\envType -> Bus.control(context.server));
		controlBus.add(\shape -> Bus.control(context.server));
		controlBus.add(\attack -> Bus.control(context.server));
		controlBus.add(\release -> Bus.control(context.server));
		controlBus.add(\amp -> Bus.control(context.server));

		SynthDef.new(\string, {
			arg out,

			// per-voice params
			t_trig = 0,
			gate = 0,
			hz = 220,
			vel = 0.5,
			pos = 0.5,
			pan = 0;

			// global params
			var envType = In.kr(controlBus[\envType]);
			var shape = In.kr(controlBus[\shape]);
			var attack = In.kr(controlBus[\attack]);
			var release = In.kr(controlBus[\release]);
			var amp = In.kr(controlBus[\amp]);

			// envelopes
			var pluck = EnvGen.ar(Env.perc(0.01, release), t_trig);
			var bow = EnvGen.ar(Env.asr(attack, 1, release), gate);

			// waveforms
			var pulse = Pulse.ar(hz, pos);
			var saw = Saw.ar(hz, hz / (1/13 + pos).min(14/13 - pos));
			var tone = LinXFade2.ar(pulse, saw, shape);

			// bring it all together
			var vol = Select.kr(envType, [pluck, bow]) * vel;
			var noise = WhiteNoise.ar(vol.linexp(0, 1, 0.01, 0.25));
			var cutoff = vol.linexp(0, 1, hz, SampleRate.ir / 2);
			Out.ar(out, Pan2.ar(LPF.ar(tone * noise + tone, cutoff), pan, vol * amp));
		}).add;

		context.server.sync;
		
		controlBus[\envType].setSynchronous(0);
		controlBus[\shape].setSynchronous(-1);
		controlBus[\attack].setSynchronous(0.01);
		controlBus[\release].setSynchronous(0.6);
		controlBus[\amp].setSynchronous(0.5);

		voices = Array.fill(8, {
			Synth.new(\string, [
				\out, context.out_b
			]);
		});
		
		this.addCommand("gate", "ii", {
			arg msg;
			var voice = voices[msg[1] - 1];
			var state = msg[2];
			msg.postln;
			voice.set(\t_trig, state);
			voice.set(\gate, state);
		});
		
		this.addCommand("hz", "if", {
			arg msg;
			var voice = voices[msg[1] - 1];
			msg.postln;
			voice.set(\hz, msg[2]);
		});
		
		this.addCommand("vel", "if", {
			arg msg;
			var voice = voices[msg[1] - 1];
			msg.postln;
			voice.set(\vel, msg[2]);
		});
		
		this.addCommand("pos", "if", {
			arg msg;
			var voice = voices[msg[1] - 1];
			msg.postln;
			voice.set(\pos, msg[2]);
		});
		
		this.addCommand("pan", "if", {
			arg msg;
			var voice = voices[msg[1] - 1];
			msg.postln;
			voice.set(\pan, msg[2]);
		});
		
		this.addCommand("env_type", "i", {
			arg msg;
			msg.postln;
			controlBus[\envType].set(msg[1] - 1);
		});
		
		this.addCommand("shape", "f", {
			arg msg;
			msg.postln;
			controlBus[\shape].set(msg[1]);
		});
		
		this.addCommand("attack", "f", {
			arg msg;
			msg.postln;
			controlBus[\attack].set(msg[1]);
		});
		
		this.addCommand("release", "f", {
			arg msg;
			msg.postln;
			controlBus[\release].set(msg[1]);
		});
		
		this.addCommand("amp", "f", {
			arg msg;
			msg.postln;
			controlBus[\amp].set(msg[1]);
		});
	}
	
	free {
		controlBus.do({ |bus| bus.free; });
		voices.do({ |synth| synth.free; });
	}
}