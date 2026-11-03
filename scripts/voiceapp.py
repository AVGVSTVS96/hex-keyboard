"""Stands in for the Hex app's Listener in the simulator, which can't record: holds the microphone lock, answers the
keyboard's start with listening and a voice's worth of levels, finish with what was "heard", and stop by ending the way
a quit app does, mid-transcription: the status stays, the lock goes. scripts/voiceapp.py <simulator id> <App Group container>
[listening], which only listens, until it's killed, for screenshots of the bar while you talk."""
import fcntl, json, math, os, struct, subprocess, sys, threading, time

simulator, group = sys.argv[1:3]
prefix = "com.shahidy.hexkeyboard.dictation"
os.makedirs(f"{group}/Library", exist_ok=True)


def notify(*arguments):
    return subprocess.Popen(["xcrun", "simctl", "spawn", simulator, "notifyutil", *arguments], stdout=subprocess.DEVNULL)


started = None


def publish(state, heard=None):
    global started
    started = None if state == "idle" else started or time.time() - 978307200
    since = {"since": started} if started else {}
    with open(f"{group}/Library/dictation.json", "w") as file:
        json.dump({"state": state, **since, **({"heard": heard} if heard else {})}, file)
    notify("-p", prefix).wait()


def speak(stop):
    step = 0
    while not stop.is_set():
        level = 0.002 + 0.12 * abs(math.sin(step * 0.9) * math.sin(step * 0.37 + 1))
        bits = struct.unpack("<I", struct.pack("<f", level))[0]
        notify("-s", f"{prefix}.level", str(bits)).wait()
        notify("-p", f"{prefix}.level").wait()
        step += 1
        stop.wait(0.1)


lock = open(f"{group}/Library/mic.lock", "w")
fcntl.flock(lock, fcntl.LOCK_EX)
if sys.argv[3:] == ["listening"]:
    publish("listening")
    speak(threading.Event())
started = notify("-1", f"{prefix}.start")
publish("idle")
started.wait()
finished = notify("-1", f"{prefix}.finish")
publish("listening")
stop = threading.Event()
voice = threading.Thread(target=speak, args=(stop,))
voice.start()
finished.wait()
stop.set()
voice.join()
stopped = notify("-1", f"{prefix}.stop")
publish("transcribing")
publish("idle", "hello from the mic")
stopped.wait()
publish("transcribing")
fcntl.flock(lock, fcntl.LOCK_UN)
lock.close()
notify("-p", prefix).wait()
