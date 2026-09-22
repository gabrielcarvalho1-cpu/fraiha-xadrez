extends SceneTree
## Original procedural sound design: modal impacts and short musical stingers.
const RATE = 44100
var random = RandomNumberGenerator.new()
func _initialize():
    random.seed = 250025
    var folder = OS.get_cmdline_user_args()[0]
    DirAccess.make_dir_recursive_absolute(folder)
    for id in ["wood","metal","capture","check","mate","win","loss","promotion","ui","castle"]:
        var seconds = {"wood":0.24,"metal":0.65,"capture":0.55,"check":0.65,"mate":1.5,"win":1.8,"loss":1.6,"promotion":1.0,"ui":0.09,"castle":12.0}[id]
        var samples = PackedFloat32Array()
        var filtered := 0.0
        var peak := 0.001
        for i in range(int(seconds*RATE)):
            var t = float(i)/RATE
            var sample := 0.0
            filtered = 0.985*filtered+0.015*random.randf_range(-1,1)
            if id == "castle":
                var fade = minf(1.0,minf(t,seconds-t)/0.7)
                sample = (filtered*2.5+sin(TAU*73*t)*0.028+sin(TAU*109*t)*0.018)*(0.8+0.2*sin(TAU*t/6))*fade
            elif id in ["wood","metal","capture","ui"]:
                var freq = {"wood":230.0,"metal":640.0,"capture":170.0,"ui":900.0}[id]
                var damping = 36.0 if id in ["wood","ui"] else 12.0
                sample = sin(TAU*freq*t)*exp(-damping*t)*0.55
                sample += sin(TAU*freq*2.76*t)*exp(-damping*1.3*t)*0.24
                sample += sin(TAU*freq*4.17*t)*exp(-damping*1.7*t)*0.10
                sample += random.randf_range(-1,1)*exp(-t*260)*0.32
                if id == "capture": sample += sin(TAU*82*t)*exp(-t*9)*0.28
            else:
                var notes: Array = {"check":[440.0,466.16],"mate":[146.83,220.0,293.66],"win":[261.63,329.63,392.0,523.25],"loss":[293.66,261.63,220.0,146.83],"promotion":[392.0,523.25,659.25]}[id]
                for n in range(notes.size()):
                    var elapsed = t-n*0.16
                    if elapsed >= 0:
                        sample += (sin(TAU*notes[n]*elapsed)+0.18*sin(TAU*notes[n]*2.01*elapsed))*exp(-elapsed*4.5)*minf(1.0,elapsed/0.01)*0.3
            sample *= minf(1.0,(seconds-t)/0.025)
            samples.append(sample)
            peak = maxf(peak,absf(sample))
        var bytes = PackedByteArray()
        bytes.resize(samples.size()*2)
        for i in range(samples.size()): bytes.encode_s16(i*2,int(samples[i]/peak*0.78*32767))
        var sound = AudioStreamWAV.new()
        sound.format = AudioStreamWAV.FORMAT_16_BITS
        sound.mix_rate = RATE
        sound.data = bytes
        if id == "castle":
            sound.loop_mode = AudioStreamWAV.LOOP_FORWARD
            sound.loop_end = samples.size()
        print("AUDIO ",id," ",sound.save_to_wav(folder+"/"+id+".wav")," duration=",seconds)
    quit()
