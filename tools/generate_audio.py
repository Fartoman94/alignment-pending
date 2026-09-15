from pathlib import Path
import wave, math, struct, random
OUT = Path(__file__).resolve().parents[1] / 'game/assets/audio'
OUT.mkdir(parents=True, exist_ok=True)
SR=44100

def wav(name, samples):
    with wave.open(str(OUT/name),'w') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(SR)
        b=bytearray()
        for x in samples:
            x=max(-1.0,min(1.0,x)); b += struct.pack('<h',int(x*32767))
        f.writeframes(b)

def synth(freq, sec, amp=.15, decay=0.0, harmonic=.0):
    out=[]
    for i in range(int(SR*sec)):
        t=i/SR; env=math.exp(-decay*t) if decay else 1
        x=math.sin(2*math.pi*freq*t)+harmonic*math.sin(2*math.pi*freq*2*t)
        out.append(x*amp*env)
    return out

def silence(sec): return [0.0]*int(SR*sec)

# Short SFX
wav('ui_click.wav', synth(920,.09,.16,45,.3))
wav('ui_error.wav', synth(180,.16,.18,10,.15)+synth(150,.14,.13,12,.1))
wav('build_place.wav', synth(260,.07,.11,35,.25)+synth(390,.08,.08,30,.2))
wav('research_complete.wav', synth(523.25,.10,.10,7)+synth(659.25,.10,.10,7)+synth(783.99,.17,.11,6))
wav('deployment_ship.wav', synth(220,.08,.08,8)+synth(329.63,.10,.09,7)+synth(440,.18,.10,5))
alert=[]
for f in (392,466.16,349.23): alert += synth(f,.14,.16,5)+silence(.035)
wav('incident_alert.wav',alert)

# Office ambience
rng=random.Random(8124); amb=[]
for i in range(SR*20):
    t=i/SR; hum=.023*math.sin(2*math.pi*60*t)+.010*math.sin(2*math.pi*120*t)
    drift=.007*math.sin(2*math.pi*.09*t); noise=(rng.random()*2-1)*.010
    amb.append(hum+drift+noise)
wav('office_ambience.wav',amb)

# Original adaptive loop family. Simple placeholders, intentionally understated.
def loop(name,bases,sec=24,tension=0.0):
    out=[]
    bars=len(bases); bar_len=sec/bars
    for i in range(SR*sec):
        t=i/SR; idx=min(bars-1,int(t//bar_len)); base=bases[idx]
        local=t%bar_len; env=.58+.24*math.sin(math.pi*local/bar_len)
        pad=(math.sin(2*math.pi*base*t)+.38*math.sin(2*math.pi*base*1.5*t)+.16*math.sin(2*math.pi*base*2*t))*.030
        pulse=math.sin(2*math.pi*(base/4)*t)*(.010+tension*.010)
        tick=(math.sin(2*math.pi*880*t)*.006 if tension and (t*2)%1<.05 else 0)
        out.append((pad+pulse+tick)*env)
    wav(name,out)
loop('menu_loop.wav',[146.83,174.61,220.0,164.81])
loop('garage_loop.wav',[130.81,155.56,196.0,146.83],24,.1)
loop('growth_loop.wav',[146.83,185.0,220.0,174.61],24,.25)
loop('incident_loop.wav',[138.59,146.83,130.81,123.47],24,.8)
print('Generated original placeholder audio in',OUT)
