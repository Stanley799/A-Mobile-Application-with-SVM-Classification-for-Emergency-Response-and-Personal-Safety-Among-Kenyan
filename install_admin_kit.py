r"""Administrator-accounts installer. ONE file, no unzipping. Put it in C:\EmergencyResponseSystem and run:  py install_admin_kit.py
Safe to run again. It only ADDS new files and makes two tiny, anchored edits (one line appended to functions\main.py, the Administrators tab in
admin_shell.dart). Anything it replaces is first copied to backup_before_admin\. If an edit cannot be applied exactly it changes nothing there and says so."""
import base64, hashlib, json, os, shutil, sys, zlib

DATA = """
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
6Dk+
"""
FILES = json.loads(zlib.decompress(base64.b64decode("".join(DATA.split()))).decode())


def find_root():
    cands = [sys.argv[1] if len(sys.argv) > 1 else None, os.path.dirname(os.path.abspath(__file__)), os.getcwd(), r"C:\EmergencyResponseSystem"]
    for c in cands:
        if c and os.path.isdir(os.path.join(c, "functions")) and os.path.isdir(os.path.join(c, "mobile")):
            return os.path.abspath(c)
    sys.exit("STOP: could not find the project folder (it must contain functions and mobile). Run this from C:\\EmergencyResponseSystem.")


ROOT = find_root()
BK = os.path.join(ROOT, "backup_before_admin")
done, skipped, problems = [], [], []


def backup(rel):
    src = os.path.join(ROOT, rel)
    if os.path.exists(src):
        dst = os.path.join(BK, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if not os.path.exists(dst):
            shutil.copy2(src, dst)


def put(rel, text):
    path = os.path.join(ROOT, *rel.split("/"))
    if os.path.exists(path):
        old = open(path, encoding="utf-8").read()
        if old == text:
            skipped.append(rel + " (already installed)")
            return
        backup(rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "w", encoding="utf-8", newline="\n").write(text)
    done.append(rel)


for rel, text in FILES.items():
    put(rel, text)

# ---- edit 1: functions\main.py gets one import line so Firebase finds the three new functions
mp = os.path.join(ROOT, "functions", "main.py")
LINE = "from admin_functions import admin_list_admins, admin_grant_admin, admin_revoke_admin  # noqa: F401,E402  (administrator accounts)"
if not os.path.exists(mp):
    problems.append("functions\\main.py not found")
else:
    s = open(mp, encoding="utf-8").read()
    if "admin_functions" in s:
        skipped.append("functions/main.py (already has the import)")
    else:
        backup("functions/main.py")
        open(mp, "w", encoding="utf-8", newline="\n").write(s.rstrip("\n") + "\n\n" + LINE + "\n")
        done.append("functions/main.py (+1 line)")

# ---- edit 2: admin_shell.dart gets the 4th tab
sp = os.path.join(ROOT, "mobile", "lib", "features", "admin", "admin_shell.dart")
EDITS = [
    ("import 'admin_incidents.dart';", "import 'admin_admins.dart';\nimport 'admin_incidents.dart';"),
    ("['Overview', 'Incidents', 'Responders']", "['Overview', 'Incidents', 'Responders', 'Administrators']"),
    ("Icons.local_shipping_outlined]", "Icons.local_shipping_outlined, Icons.admin_panel_settings_outlined]"),
    ("                _ => AdminResponders(repo: repo, responders: responders),", "                2 => AdminResponders(repo: repo, responders: responders),\n                _ => const AdminAdmins(),"),
]
if not os.path.exists(sp):
    problems.append("admin_shell.dart not found (is Phase 2 installed?)")
else:
    s = open(sp, encoding="utf-8").read()
    if "AdminAdmins" in s:
        skipped.append("admin_shell.dart (already has the tab)")
    elif all(s.count(a) == 1 for a, _ in EDITS) and s.count("i < 3;") == 2:
        backup("mobile/lib/features/admin/admin_shell.dart")
        for a, b in EDITS:
            s = s.replace(a, b)
        s = s.replace("i < 3;", "i < _titles.length;")
        open(sp, "w", encoding="utf-8", newline="\n").write(s)
        done.append("admin_shell.dart (Administrators tab)")
    else:
        problems.append("admin_shell.dart differs from what was expected: NOT changed. The agent must add the Administrators tab by hand (see prompt Step 2b).")

print("ROOT:", ROOT)
for d in done:
    print("  installed:", d)
for d in skipped:
    print("  skipped  :", d)
for d in problems:
    print("  PROBLEM  :", d)
print("INSTALL OK" if not problems else "INSTALL DONE WITH PROBLEMS")
