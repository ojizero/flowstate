#!/usr/bin/env python3
"""Manage only the Flow State bundle built in this checkout."""
from pathlib import Path
import os
import signal
import subprocess
import sys
import time

root = Path(__file__).resolve().parents[2]
bundle = root / "build" / "Flow State.app"
executable = str(bundle / "Contents" / "MacOS" / "FlowState")


def running_pids():
    output = subprocess.check_output(["/bin/ps", "-axo", "pid=,command="], text=True)
    matches = []
    for line in output.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) != 2:
            continue
        pid, command = fields
        if command == executable or command.startswith(executable + " "):
            matches.append(int(pid))
    return matches


def stop():
    pids = running_pids()
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    for _ in range(50):
        if not running_pids():
            print("Flow State stopped." if pids else "Flow State is not running.")
            return
        time.sleep(0.1)
    raise SystemExit("Flow State is still running. Close it before restarting or cleaning.")


action = sys.argv[1]
if action == "status":
    pids = running_pids()
    print("Flow State running: " + ", ".join(map(str, pids)) if pids else "Flow State is not running.")
elif action == "stop":
    stop()
elif action == "start":
    if running_pids():
        raise SystemExit("Flow State is already running from this checkout. Use mise run restart to reload it.")
    if not Path(executable).is_file():
        raise SystemExit("Build the app first with mise run bundle, or use mise run dev.")
    log_dir = root / "build" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    subprocess.run(["/usr/bin/open", "-n", "--stdout", str(log_dir / "app.stdout.log"),
                    "--stderr", str(log_dir / "app.stderr.log"), str(bundle), "--args", *sys.argv[2:]], check=True)
    for _ in range(50):
        if running_pids():
            print("Started Flow State.")
            break
        time.sleep(0.1)
    else:
        raise SystemExit("No running Flow State process found. Check build/logs for launch errors.")
else:
    raise SystemExit("Expected start, stop, or status.")
