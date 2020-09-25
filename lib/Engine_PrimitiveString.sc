Engine_PrimitiveString : CroneEngine {
	classvar numVoices = 27;

	var controlBus;
	var voices;
	
	*new { arg context, doneCallback;
		^super.new(context, doneCallback);
	}

	alloc {
		
		controlBus = Dictionary.new;
		controlBus.add(\envType -> Bus.control(context.server));
		controlBus.add(\shape -> Bus.control(context.server));
		controlBus.add(\noisiness -> Bus.control(context.server));
		controlBus.add(\ringiness -> Bus.control(context.server));
		controlBus.add(\brightness -> Bus.control(context.server));
		controlBus.add(\attack -> Bus.control(context.server));
		controlBus.add(\release -> Bus.control(context.server));
		controlBus.add(\amp -> Bus.control(context.server));

		SynthDef.new(\string, {
			arg out,

			// per-voice params
			t_trig = 0,
			gate = 0,
			hz = 220,
			vel = 0,
			pos = 0.5,
			pan = 0;

			// global params
			var envType = In.kr(controlBus[\envType]);
			var shape = In.kr(controlBus[\shape]);
			var noisiness = In.kr(controlBus[\noisiness]);
			var ringiness = In.kr(controlBus[\ringiness]);
			var brightness = In.kr(controlBus[\brightness]);
			var attack = In.kr(controlBus[\attack]);
			var release = In.kr(controlBus[\release]);
			var amp = In.kr(controlBus[\amp]);

			// envelopes
			var pluck = EnvGen.ar(Env.perc(attack, release), t_trig);
			var bow = EnvGen.ar(Env.asr(attack, 1, release), gate);
			var vol = Select.kr(envType, [pluck, bow]) * Lag.kr(vel, 0.01).abs.distort;

			// waveforms
			var posSmooth = Lag.kr(pos.min(1 - pos), 0.01).max(1/32); // should never really be 0, DC is no fun
			var hzSmooth = Lag.kr(hz, 0.01);

			var pulse = Pulse.ar(hzSmooth, posSmooth);
			var noise = WhiteNoise.ar(vol * vol * vol * vol * noisiness);
			var nulse = ((pulse + 1) * noise).distort + pulse;

			var saw = Saw.ar(hzSmooth);
			var comb_delay = posSmooth / hzSmooth;
			var comb_decay = vol * ringiness;
			var comb_factor = 0.001 ** (comb_delay / comb_decay); // TODO: can you skip this for better efficiency?
			var comb = CombL.ar(saw, 1/16, comb_delay, comb_decay) * comb_factor;
			var caw = comb.distort + saw;

			// bring it all together
			var tone = SelectX.ar(shape, [nulse, caw]);
			var nyquist = SampleRate.ir / 2;
			var cutoff = vol.linexp(0, 1, hzSmooth, brightness * nyquist).min(nyquist);
			Out.ar(out, Pan2.ar(SVF.ar(tone, cutoff), pan, vol * amp));
		}).add;

		context.server.sync;
		
		controlBus[\envType].setSynchronous(0);
		controlBus[\shape].setSynchronous(-1);
		controlBus[\noisiness].setSynchronous(0.25);
		controlBus[\ringiness].setSynchronous(0.2);
		controlBus[\brightness].setSynchronous(0.7);
		controlBus[\attack].setSynchronous(0.01);
		controlBus[\release].setSynchronous(0.6);
		controlBus[\amp].setSynchronous(0.5);

		voices = Array.fill(numVoices, {
			Synth.new(\string, [
				\out, context.out_b
			]);
		});
		
		this.addCommand("trig", "i", {
			arg msg;
			var voice = voices[msg[1] - 1];
			// msg.postln;
			voice.set(\t_trig, 1);
		});

		this.addCommand("gate", "ii", {
			arg msg;
			var voice = voices[msg[1] - 1];
			var state = msg[2];
			// msg.postln;
			voice.set(\gate, state);
		});
		
		this.addCommand("hz", "if", {
			arg msg;
			var voice = voices[msg[1] - 1];
			// msg.postln;
			voice.set(\hz, msg[2]);
		});
		
		this.addCommand("vel", "if", {
			arg msg;
			var voice = voices[msg[1] - 1];
			// msg.postln;
			voice.set(\vel, msg[2]);
		});
		
		this.addCommand("pos", "if", {
			arg msg;
			var voice = voices[msg[1] - 1];
			// msg.postln;
			voice.set(\pos, msg[2]);
		});
		
		this.addCommand("pan", "if", {
			arg msg;
			var voice = voices[msg[1] - 1];
			// msg.postln;
			voice.set(\pan, msg[2]);
		});
		
		this.addCommand("env_type", "i", {
			arg msg;
			// msg.postln;
			controlBus[\envType].set(msg[1] - 1);
		});
		
		this.addCommand("shape", "f", {
			arg msg;
			// msg.postln;
			controlBus[\shape].set(msg[1]);
		});
		
		this.addCommand("noisiness", "f", {
			arg msg;
			// msg.postln;
			controlBus[\noisiness].set(msg[1]);
		});
		
		this.addCommand("ringiness", "f", {
			arg msg;
			// msg.postln;
			controlBus[\ringiness].set(msg[1]);
		});
		
		this.addCommand("brightness", "f", {
			arg msg;
			// msg.postln;
			controlBus[\brightness].set(msg[1]);
		});

		this.addCommand("attack", "f", {
			arg msg;
			// msg.postln;
			controlBus[\attack].set(msg[1]);
		});
		
		this.addCommand("release", "f", {
			arg msg;
			// msg.postln;
			controlBus[\release].set(msg[1]);
		});
		
		this.addCommand("amp", "f", {
			arg msg;
			// msg.postln;
			controlBus[\amp].set(msg[1]);
		});
	}
	
	free {
		controlBus.do({ |bus| bus.free; });
		voices.do({ |synth| synth.free; });
	}
}