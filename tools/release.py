#!/usr/bin/env python3
"""Release workflow: one run builds the zips of every device and publishes them in one GitHub release.

usage: python tools/release.py [--dry-run]

Version: only the root VERSION file (X.Y.Z); build.py writes version=vX.Y.Z and
versionCode=X*10000+Y*100+Z into each zipped module.prop. Tag and release: vX.Y.Z (on the current HEAD).

Steps: checks (branch main, clean worktree, in sync with origin/main, tag not used, versionCode
increases over every existing vX.Y.Z tag, gh logged in) -> build.py -> verify every zip -> release
notes from RELEASE_NOTES.md -> annotated tag -> push tag -> gh release create.
--dry-run stops after the release notes (nothing is tagged or pushed).
"""
import io
import os
import re
import subprocess
import sys
import zipfile
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import build  # noqa: E402  (zip naming shared with build.py)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = "XPRAMT/ksu-hires-unlocker"
REQUIRED = ("module.prop", "common.sh", "device.sh", "customize.sh", "post-fs-data.sh", "service.sh")
ALLOWED_EXT = (".sh", ".prop", ".py")       # anything else in a zip (.so, .xml, binaries) is refused


def fail(msg):
    sys.stderr.write("ERROR: %s\n" % msg)
    sys.exit(1)


def run(*cmd, check=True):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True)
    out = r.stdout.decode("utf-8", "replace").strip()
    if check and r.returncode:
        fail("%s failed:\n%s" % (" ".join(cmd), (out + "\n" + r.stderr.decode("utf-8", "replace")).strip()))
    return out if check else (r.returncode, out)


def rd(path):
    return io.open(path, encoding="utf-8", newline="").read()


def wr(path, text):
    io.open(path, "w", encoding="utf-8", newline="").write(text)


def devices():
    d = os.path.join(ROOT, "devices")
    return sorted(x for x in os.listdir(d) if os.path.isfile(os.path.join(d, x, "device.sh"))
                  and os.path.isfile(os.path.join(d, x, "module.prop")))


def prop(text, key):
    m = re.search(r"^%s=(.*)$" % re.escape(key), text, re.M)
    if not m:
        fail("module.prop has no %s=" % key)
    return m.group(1).strip()


def main():
    dry = "--dry-run" in sys.argv[1:]
    unknown = [a for a in sys.argv[1:] if a != "--dry-run"]
    if unknown:
        fail("unknown argument: " + " ".join(unknown))
    print("== %s" % ("DRY RUN (build and verify only)" if dry else "RELEASE"))

    tag, code = build.version()
    print("version %s, versionCode %d, tag %s" % (tag, code, tag))

    # --- repository checks
    branch = run("git", "rev-parse", "--abbrev-ref", "HEAD")
    if branch != "main":
        fail("not on main (on %s)" % branch)
    if run("git", "status", "--porcelain"):
        fail("worktree is not clean (commit or stash first):\n" + run("git", "status", "--short"))
    run("git", "fetch", "-q", "origin", "main", "--tags")
    head, remote = run("git", "rev-parse", "HEAD"), run("git", "rev-parse", "origin/main")
    if head != remote:
        fail("main is not in sync with origin/main (local %s, origin %s)" % (head[:7], remote[:7]))
    if run("git", "tag", "-l", tag):
        fail("tag %s already exists locally" % tag)
    if run("git", "ls-remote", "--tags", "origin", "refs/tags/" + tag):
        fail("tag %s already exists on origin" % tag)
    if not dry:
        rc, _ = run("gh", "auth", "status", check=False)
        if rc:
            fail("gh is not logged in (gh auth login)")
        rc, _ = run("gh", "release", "view", tag, "-R", REPO, check=False)
        if rc == 0:
            fail("release %s already exists on GitHub" % tag)
    print("checks ok: main, clean, in sync with origin, tag free")

    devs = devices()
    if not devs:
        fail("no device in devices/")
    print("devices: " + ", ".join(devs))

    # --- versionCode must increase over every released vX.Y.Z (legacy hires-mixer-v0.x used versionCode <= 11)
    for t in run("git", "tag", "-l", "v*").split():
        mt = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", t)
        if mt and int(mt.group(1)) * 10000 + int(mt.group(2)) * 100 + int(mt.group(3)) >= code:
            fail("versionCode %d is not greater than tag %s (raise VERSION)" % (code, t))
    if code <= 11:
        fail("versionCode %d must be greater than 11 (v0.8.0)" % code)

    # --- build
    dist = os.path.join(ROOT, "dist")
    expected = {}
    for d in devs:
        mod_id = prop(rd(os.path.join(ROOT, "devices", d, "module.prop")), "id")
        model = build.zip_model(open(os.path.join(ROOT, "devices", d, "device.sh"), "rb").read())
        expected[d] = (mod_id, os.path.join(dist, build.zip_name(model, tag)))
        if os.path.exists(expected[d][1]):
            os.remove(expected[d][1])
    run(sys.executable, os.path.join(ROOT, "build.py"), *devs)

    # --- verify
    for d in devs:
        mod_id, path = expected[d]
        if not os.path.isfile(path):
            fail("%s: %s was not built" % (d, os.path.relpath(path, ROOT)))
        with zipfile.ZipFile(path) as zf:
            names = zf.namelist()
            for r in REQUIRED:
                if r not in names:
                    fail("%s: %s missing in the zip" % (d, r))
            for n in names:
                if n.startswith(("system/", "original/")) or not n.endswith(ALLOWED_EXT):
                    fail("%s: unexpected file in the zip (vendor file?): %s" % (d, n))
                if b"\r" in zf.read(n):
                    fail("%s: CRLF in %s" % (d, n))
            mp = zf.read("module.prop").decode("utf-8")
            if prop(mp, "id") != mod_id or prop(mp, "version") != tag or prop(mp, "versionCode") != str(code):
                fail("%s: module.prop in the zip does not match (id/version/versionCode)" % d)
        print("  verified %s (%d files, %d bytes)" % (os.path.relpath(path, ROOT), len(names), os.path.getsize(path)))

    # --- release notes
    src = re.sub(r"<!--.*?-->", "", rd(os.path.join(ROOT, "RELEASE_NOTES.md")), flags=re.S)
    if "TODO" in src:
        if not dry:
            fail("RELEASE_NOTES.md still contains TODO")
        print("  warning: RELEASE_NOTES.md still contains TODO (a real release would stop here)")
    mz = re.search(r"^## 繁體中文\s*\n(.*?)(?=^## English)", src, re.S | re.M)
    me = re.search(r"^## English\s*\n(.*)", src, re.S | re.M)
    if not mz or not me or not mz.group(1).strip() or not me.group(1).strip():
        fail("RELEASE_NOTES.md needs a '## 繁體中文' section followed by a '## English' section")
    rows_tw = "\n".join("| %s | `%s` | `%s` |" % (d, expected[d][0], os.path.basename(expected[d][1])) for d in devs)
    notes = ("## 繁體中文\n\n" + mz.group(1).strip() + "\n\n### 下載\n\n每台裝置一個 zip，請下載自己裝置的那一個，在 KernelSU 管理器安裝後重新開機。KernelSU 一律需要掛載用的 metamodule，例如 Hybrid Mount（永久與臨時 root 皆同），且須實際掛載成功模組才會生效。\n\n"
             "| 裝置 | 模組 id | 檔案 |\n|---|---|---|\n" + rows_tw + "\n\n---\n\n"
             "## English\n\n" + me.group(1).strip() + "\n\n### Downloads\n\nOne zip per device: download the one for your device, install it in the KernelSU manager and reboot. KernelSU always needs a mount metamodule such as Hybrid Mount (permanent and temporary root alike), and the module only works when it mounts successfully.\n\n"
             "| Device | Module id | File |\n|---|---|---|\n" + rows_tw + "\n")
    notes_path = os.path.join(dist, "release-notes-%s.md" % tag)
    wr(notes_path, notes)
    print("  release notes: %s" % os.path.relpath(notes_path, ROOT))

    if dry:
        print("== dry run ok: nothing tagged or pushed")
        return

    # --- tag, push, release
    run("git", "tag", "-a", tag, "-m", "Hi-Res Unlocker %s" % tag)
    run("git", "push", "-q", "origin", tag)
    url = run("gh", "release", "create", tag, *[expected[d][1] for d in devs], "-R", REPO, "--verify-tag",
              "--title", "Hi-Res Unlocker %s" % tag, "-F", notes_path, "--latest")
    print("== released: " + url)
    print("next: clear RELEASE_NOTES.md (back to the TODO template) for the next release")


if __name__ == "__main__":
    main()
