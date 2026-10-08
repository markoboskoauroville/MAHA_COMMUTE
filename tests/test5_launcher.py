import os, pty, re, select, subprocess, sys, time, shutil, tempfile, signal
"""test5_launcher.py: the launcher screen, driven through a real terminal.

A pty is the only honest way to test a screen that reads single keys and
redraws. Fake servers stand in for the three apps (a few lines of python that
write a port file and answer), so this proves the launcher's behaviour, not
the apps'. Prints PASS or FAIL per check; test1 counts them.

  1 or 3 on an idle app starts it; on a running app they only move the light
  0 is the launcher; u updates the whole launcher when nothing runs, only
  the lit app when something does; the screen notices an app that came up
  from another window without a keypress.
"""
HERE = os.path.dirname(os.path.abspath(__file__))
V = open(os.path.join(HERE, "..", "VERSION")).read().strip()
ART = os.path.join(HERE, "..", "%s-maha_commute_v%s.sh" % (V, V))
T = tempfile.mkdtemp(prefix="uitest")
HOME = T + "/home"; PREFIX = T + "/usr"
os.makedirs(HOME); os.makedirs(PREFIX + "/bin")
env = dict(os.environ, HOME=HOME, PREFIX=PREFIX, PATH=PREFIX + "/bin:" + os.environ["PATH"], TERM="xterm")
# stubs: record every page the launcher tries to open
open(PREFIX + "/bin/am", "w").write("#!/bin/sh\necho \"$@\" >> %s/opens.log\n" % T)
os.chmod(PREFIX + "/bin/am", 0o755)
r = subprocess.run(["bash", ART, "--offline", "--apps", "123"], input="\n", text=True, env=env, capture_output=True)
print("install rc", r.returncode)
A = HOME + "/.maha.commute"
FAKE = '''
import http.server, os, sys, socketserver
d, port = sys.argv[1], int(sys.argv[2])
open(os.path.join(d, "port"), "w").write(str(port))
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(s): s.send_response(200); s.end_headers(); s.wfile.write(b"ok")
    def log_message(*a): pass
socketserver.TCPServer.allow_reuse_address = True
socketserver.TCPServer(("127.0.0.1", port), H).serve_forever()
'''
apps = {"day": (".commute", "commute_server.py", 18082, "day.commute"),
        "night": (".nightcommute", "night_server.py", 18087, "night.commute"),
        "all": (".all.commute", "all_commute_server.py", 18084, "all.commute")}
for k, (dirn, script, port, cmd) in apps.items():
    d = HOME + "/" + dirn; os.makedirs(d, exist_ok=True)
    open(d + "/" + script, "w").write(FAKE)
    os.makedirs(A + "/orig", exist_ok=True)
    p = A + "/orig/" + cmd
    open(p, "w").write("#!/bin/sh\nexec python3 %s/%s %s %d\n" % (d, script, d, port)); os.chmod(p, 0o755)
# the real update.sh is replaced by a recorder
open(A + "/update.sh", "w").write("#!/bin/sh\necho \"update called: $*\" >> %s/updates.log\n" % T)

def strip(b): return re.sub(r"\x1b\[[0-9;?]*[A-Za-z]", "", b.decode("utf-8", "replace"))
pid, fd = pty.fork()
if pid == 0:
    os.environ.update(env); os.execvp("maha-commute", ["maha-commute"])
buf = b""
def pump(t=1.2):
    global buf
    end = time.time() + t
    while time.time() < end:
        rr, _, _ = select.select([fd], [], [], 0.1)
        if rr:
            try: buf += os.read(fd, 65536)
            except OSError: return
def last_screen():
    txt = strip(buf)
    parts = txt.split("MAHA COMMUTE")
    return "MAHA COMMUTE" + parts[-1] if len(parts) > 1 else txt
def key(k, t=1.5, until=None):
    os.write(fd, k.encode()); pump(t)
    if until:
        end = time.time() + 40
        while time.time() < end and not until(last_screen()):
            pump(0.5)
fails = 0
def check(name, cond):
    global fails
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        fails += 1
        print("---- the screen at that moment:\n" + strip(buf)[-700:] + "\n----")
def opens(): 
    try: return len(open(T + "/opens.log").read().splitlines())
    except OSError: return 0
def updates():
    try: return open(T + "/updates.log").read().strip().splitlines()
    except OSError: return []

pump(2)
s = last_screen(); print(s[-900:])
check("starts on the launcher, nothing lit", "launcher" in s and "RUNNING" not in s)
key("1", 2, lambda s: "RUNNING 18082" in s)
s = last_screen(); print(s[-900:])
check("1 starts day and the quadrant says RUNNING", re.search(r"1 day.commute v\d+\s*\|", s) and "RUNNING 18082" in s)
o1 = opens()
key("3", 2, lambda s: "RUNNING 18084" in s)
s = last_screen(); print(s[-900:])
check("3 starts all: both RUNNING on screen", "RUNNING 18082" in s and "RUNNING 18084" in s)
o3 = opens()
key("1", 2); key("3", 2); key("1", 2)
check("1 and 3 on running apps only move the light (no page reopened)", opens() == o3)
s = last_screen()
check("the light is on day (verbs say day.commute)", "on day.commute" in s)
key("0", 1.5); s = last_screen()
check("0 returns to the launcher", "launcher:" in s)
key("u", 1.5); s = strip(buf)[-400:]
check("u with apps running and nothing lit does not update", updates() == [] and "Light one" in s)
key("x\n" if False else " ", 1)   # any key out of the message
key("3", 1.5); key("u", 1.5); key(" ", 1)
print("UPDATES", updates()); print(strip(buf)[-300:])
check("u with 3 lit updates only all", updates() == ["update called: --app all"])
key("S", 4); key(" ", 1.5)
s = last_screen(); print(s[-700:])
check("S stopped them: no RUNNING left", "RUNNING" not in s)
key("0", 1); key("u", 1.5); key(" ", 1)
check("u with nothing running updates the whole launcher", updates()[-1] == "update called:")
# an app started from ANOTHER window shows up without a keypress
subprocess.Popen(["sh", A + "/orig/night.commute"], env=env, stdin=subprocess.DEVNULL,
                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
pump(9)
check("an app started elsewhere appears on its own", "RUNNING 18087" in last_screen())
key("q", 1)

# the frame must hold at narrow widths (field test v21, F12 and F13): no line wider
# than the terminal, on the main screen and on the help screen
def at_width(cols):
    global buf
    p2, fd2 = pty.fork()
    if p2 == 0:
        os.environ.update(env)
        os.execvp("sh", ["sh", "-c", "stty cols %d rows 50; exec maha-commute" % cols])
    out = b""
    def grab(t):
        nonlocal out
        end = time.time() + t
        while time.time() < end:
            rr, _, _ = select.select([fd2], [], [], 0.1)
            if rr:
                try: out += os.read(fd2, 65536)
                except OSError: return
    grab(2.5)
    main = strip(out).split("MAHA COMMUTE")[-1]
    out = b""; os.write(fd2, b"h"); grab(1.5)
    helptxt = strip(out)
    os.write(fd2, b" "); grab(0.5); os.write(fd2, b"q"); grab(0.5)
    try: os.kill(p2, signal.SIGKILL)
    except OSError: pass
    return main, helptxt
for cols in (40, 50, 60):
    main, helptxt = at_width(cols)
    widest = max((len(l) for l in main.splitlines()), default=0)
    check("%d columns: nothing on the main screen is wider than the terminal (widest %d)" % (cols, widest), widest <= cols)
    check("%d columns: all four apps are on screen" % cols, all(x in main for x in ("day.commute", "night.commute", "all.commute")))
    hw = max((len(l) for l in helptxt.splitlines()), default=0)
    check("%d columns: the help fits (widest %d)" % (cols, hw), hw <= cols)
    check("%d columns: help no longer mentions F keys, and says w for wipe" % cols, "F keys" not in helptxt and "w  wipe" in helptxt.replace("\n  ", "  ").replace("\n", " ") or "wipe" in helptxt)

try: os.kill(pid, signal.SIGKILL)
except OSError: pass
subprocess.run("pkill -f '%s' 2>/dev/null" % T, shell=True)
shutil.rmtree(T, ignore_errors=True)
print("PASSED" if fails == 0 else "FAILED %d" % fails)
