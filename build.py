#!/usr/bin/env python3
"""Build one KernelSU module zip per device: dist/bt_hires_mixer_<ZIP_MODEL>_v<version>.zip
(ZIP_MODEL is set in devices/<device>/device.sh, e.g. NX809J, XiaomiPad6Pro).

usage: python build.py [device ...]      (default: every folder in devices/)

Zip layout (flat, LF line endings):
  module.prop            devices/<device>/module.prop
  common.sh              common/lib.sh
  device.sh              devices/<device>/device.sh
  customize.sh           common/customize.sh
  post-fs-data.sh        common/post-fs-data.sh
  tools/*.py             devices/<device>/tools/*.py (PC reference implementations)
"""
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
STAMP = (2026, 1, 1, 0, 0, 0)          # fixed timestamp: same input gives the same zip


def read(path):
    data = open(path, "rb").read()
    assert b"\r" not in data, "CRLF in " + path
    return data


def prop(data, key):
    for line in data.decode("utf-8").splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1].strip()
    raise SystemExit("%s missing in module.prop" % key)


def zip_model(device_sh):
    m = re.search(rb"^ZIP_MODEL=([A-Za-z0-9]+)", device_sh, re.M)
    if not m:
        raise SystemExit("ZIP_MODEL missing in device.sh")
    return m.group(1).decode()


def zip_name(model, version):
    return "bt_hires_mixer_%s_%s.zip" % (model, version)


def build(device):
    ddir = os.path.join(ROOT, "devices", device)
    mp = read(os.path.join(ddir, "module.prop"))
    mod_id, version = prop(mp, "id"), prop(mp, "version")
    files = [
        ("module.prop", mp),
        ("common.sh", read(os.path.join(ROOT, "common", "lib.sh"))),
        ("device.sh", read(os.path.join(ddir, "device.sh"))),
        ("customize.sh", read(os.path.join(ROOT, "common", "customize.sh"))),
        ("post-fs-data.sh", read(os.path.join(ROOT, "common", "post-fs-data.sh"))),
    ]
    tdir = os.path.join(ddir, "tools")
    if os.path.isdir(tdir):
        for name in sorted(os.listdir(tdir)):
            if name.endswith(".py"):
                files.append(("tools/" + name, read(os.path.join(tdir, name))))
    os.makedirs(os.path.join(ROOT, "dist"), exist_ok=True)
    out = os.path.join(ROOT, "dist", zip_name(zip_model(read(os.path.join(ddir, "device.sh"))), version))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files:
            info = zipfile.ZipInfo(name, STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o100755 if name.endswith(".sh") else 0o100644) << 16
            z.writestr(info, data)
    print(os.path.relpath(out, ROOT))


if __name__ == "__main__":
  devices = sys.argv[1:] or sorted(
    d for d in os.listdir(os.path.join(ROOT, "devices"))
    if os.path.isfile(os.path.join(ROOT, "devices", d, "device.sh")))
  for d in devices:
    build(d)
