"""Stands in for the Hex app's Listener in the simulator, which can't record: holds the microphone lock, answers the
keyboard's start with listening and a voice's worth of levels, and finish with writing it down. The first waits for the
model to get ready, and meanwhile the keyboard starts a second; the first is typed as the second records. Stop ends the way a quit app
does, mid-writing: the status stays, the lock goes. scripts/voiceapp.py <simulator id> <App Group container>
[listening], which only listens, until it's killed, for screenshots of the bar while you talk."""
import fcntl, json, math, os, struct, subprocess, sys, threading, time

simulator, group = sys.argv[1:3]
prefix = "com.shahidy.hexkeyboard.dictation"
os.makedirs(f"{group}/Library", exist_ok=True)


def notify(*arguments):
    return subprocess.Popen(["xcrun", "simctl", "spawn", simulator, "notifyutil", *arguments], stdout=subprocess.DEVNULL)


began = None


def publish(listening=False, writing=(), heard=(), waiting=False):
    global began
    if listening:
        began = time.time() - 978307200
    status = {"listening": listening, "writing": list(writing), "heard": list(heard)}
    if waiting:
        status["waiting"] = "Model loading…"
    if began and (listening or writing):
        status["since"] = began
    with open(f"{group}/Library/dictation.json", "w") as file:
        json.dump(status, file)
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


def listen(finished):
    stop = threading.Event()
    voice = threading.Thread(target=speak, args=(stop,))
    voice.start()
    finished.wait()
    stop.set()
    voice.join()


lock = open(f"{group}/Library/mic.lock", "w")
fcntl.flock(lock, fcntl.LOCK_EX)
if sys.argv[3:] == ["listening"]:
    publish(listening=True)
    speak(threading.Event())
started = notify("-1", f"{prefix}.start")
publish()
started.wait()
finished = notify("-1", f"{prefix}.finish")
publish(listening=True)
listen(finished)
started = notify("-1", f"{prefix}.start")
publish(writing=[5.2], waiting=True)
started.wait()
finished = notify("-1", f"{prefix}.finish")
publish(listening=True, writing=[5.2], waiting=True)
time.sleep(3)
publish(listening=True, heard=["hello from the mic"])
listen(finished)
stopped = notify("-1", f"{prefix}.stop")
publish(writing=[2.8])
publish(heard=["and again"])
stopped.wait()
publish(writing=[2.8])
fcntl.flock(lock, fcntl.LOCK_UN)
lock.close()
notify("-p", prefix).wait()
