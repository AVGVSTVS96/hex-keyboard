"""Stands in for the Hex app's Listener in the simulator, which can't record: holds the microphone lock, answers the
keyboard's start with listening and a voice's worth of levels, and finish with writing it down for the keyboard that
stopped it. The first waits for the model to get ready, and meanwhile the keyboard starts a second; the first is typed as
the second records. Then it leaves one for a keyboard that has closed, which isn't typed. The last dictation ends the way a
quit app does, mid-writing: the status stays, the lock goes. scripts/voiceapp.py <simulator id> <App Group container>
[listening|saved|waiting], which holds one state until it's killed, for screenshots of the bar: talking; talking with two
saved; three saved waiting for the model."""
import fcntl, json, math, os, struct, subprocess, sys, threading, time, uuid

simulator, group = sys.argv[1:3]
prefix = "com.shahidy.hexkeyboard.dictation"
os.makedirs(f"{group}/Library/notes", exist_ok=True)
for left in os.listdir(f"{group}/Library/notes"):
    os.remove(f"{group}/Library/notes/{left}")


def notify(*arguments):
    return subprocess.Popen(["xcrun", "simctl", "spawn", simulator, "notifyutil", *arguments], stdout=subprocess.DEVNULL)


def publish(listening=False, writing=(), waiting=False):
    status = {"listening": listening, "writing": list(writing)}
    if waiting:
        status["waiting"] = "Model loading…"
    with open(f"{group}/Library/dictation.json", "w") as file:
        json.dump(status, file)
    notify("-p", prefix).wait()


def leave(text, keyboard):
    note = {"heard": {"_0": text, **({"keyboard": keyboard} if keyboard else {})}}
    name = f"{group}/Library/notes/{time.time_ns():020d}-{uuid.uuid4()}.json"
    with open(name + ".tmp", "w") as file:
        json.dump(note, file)
    os.rename(name + ".tmp", name)
    notify("-p", prefix).wait()


def keyboard(signal):
    """The keyboard that sent `signal`, from the notification's state."""
    out = subprocess.run(["xcrun", "simctl", "spawn", simulator, "notifyutil", "-g", f"{prefix}.{signal}"], capture_output=True, text=True).stdout
    return int(out.split()[-1]) or None


def speak(stop):
    """A voice's levels, each with the seconds recorded so far, as the app's microphone publishes them."""
    step, began = 0, time.time()
    while not stop.is_set():
        level = 0.002 + 0.12 * abs(math.sin(step * 0.9) * math.sin(step * 0.37 + 1))
        bits = struct.unpack("<I", struct.pack("<f", level))[0]
        recorded = int((time.time() - began) * 1000)
        notify("-s", f"{prefix}.level", str(recorded << 32 | bits)).wait()
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
if sys.argv[3:] == ["saved"]:
    publish(listening=True, writing=[5.2, 3.1], waiting=True)
    speak(threading.Event())
if sys.argv[3:] == ["waiting"]:
    publish(writing=[5.2, 3.1, 8.4], waiting=True)
    threading.Event().wait()
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
first = keyboard("finish")
publish(listening=True)
leave("hello from the mic", first)
listen(finished)
started = notify("-1", f"{prefix}.start")
publish(writing=[2.8])
publish()
leave("and again", keyboard("finish"))
leave("said elsewhere", 1)
started.wait()
finished = notify("-1", f"{prefix}.finish")
publish(listening=True)
listen(finished)
publish(writing=[2.8])
fcntl.flock(lock, fcntl.LOCK_UN)
lock.close()
notify("-p", prefix).wait()
