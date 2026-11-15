# Instructor check for top_errors (Codex audit 2026-11-14 finding 8). Runs against the
# learner's logparse.py with cases they never saw; their own test file plays no part.
import copy
import sys

sys.path.insert(0, ".")
from logparse import top_errors  # noqa: E402


def rec(sev, msg):
    return {"severity": sev, "message": msg, "pid": 7}


R = [rec("ERROR", "disk full"), rec("FATAL", "no space left"), rec("ERROR", "disk full"),
     rec("LOG", "checkpoint"), rec("WARNING", "slow query"), rec("FATAL", "no space left"),
     rec("ERROR", "disk full"), rec("ERROR", "timeout"), rec("PANIC", "not counted")]
fails = []


def check(name, fn):
    try:
        if not fn():
            fails.append(name)
    except Exception as e:  # noqa: BLE001
        fails.append(f"{name} ({type(e).__name__})")


def raises(n):
    try:
        top_errors(R, n)
    except ValueError:
        return True
    return False


check("counts only ERROR and FATAL, most frequent first",
      lambda: top_errors(R, 10) == [("disk full", 3), ("no space left", 2), ("timeout", 1)])
check("n limits the result", lambda: top_errors(R, 1) == [("disk full", 3)])
check("default n is 3", lambda: len(top_errors(R + [rec("ERROR", "x"), rec("FATAL", "y")])) == 3)
check("ties break alphabetically",
      lambda: top_errors([rec("FATAL", "zeta"), rec("ERROR", "alpha"), rec("ERROR", "mid")], 3)
      == [("alpha", 1), ("mid", 1), ("zeta", 1)])
check("empty input gives []", lambda: top_errors([], 4) == [])
check("no ERROR/FATAL gives []", lambda: top_errors([rec("LOG", "a"), rec("WARNING", "b")]) == [])
check("n = 0 raises ValueError", lambda: raises(0))
check("negative n raises ValueError", lambda: raises(-2))


def unchanged():
    before = copy.deepcopy(R)
    top_errors(R, 2)
    return R == before


check("input is not changed", unchanged)
for f in fails:
    print("FAIL:", f)
sys.exit(1 if fails else 0)
