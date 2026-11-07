#!/usr/bin/env python3

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MOD_SRC = ROOT / "mod" / "SandboxToolbox"
VENDOR = ROOT / "vendor" / "ModMenu"
BRIDGE_SRC = ROOT / "native" / "native_bridge.c"
LICENSE = ROOT / "LICENSE"
DIST = ROOT / "dist"
STAGE = DIST / "stage"
DLL = ROOT / "build" / "native_bridge.dll"
MINGW = os.environ.get("MINGW_CC", "x86_64-w64-mingw32-gcc")
ZIP_TIME = (2026, 1, 1, 0, 0, 0)


def run(cmd, **kw):
    print("+", " ".join(map(str, cmd)))
    subprocess.run(cmd, check=True, **kw)


def version():
    text = (MOD_SRC / "Scripts" / "toolbox" / "version.lua").read_text()
    m = re.search(r'return\s+"(\d+\.\d+\.\d+)"', text)
    if not m:
        sys.exit('version.lua: expected `return "MAJOR.MINOR.PATCH"`')
    return m.group(1)


def lint():
    luac = shutil.which("luac5.4") or shutil.which("luac")
    if not luac:
        sys.exit("luac not found; cannot syntax-check Lua")
    files = sorted(str(p) for p in MOD_SRC.rglob("*.lua"))
    run([luac, "-p", *files])


def build_dll():
    if not shutil.which(MINGW):
        sys.exit(
            f"{MINGW} not found. Install mingw-w64 (or set MINGW_CC); the People card needs the DLL."
        )
    DLL.parent.mkdir(exist_ok=True)
    run(
        [
            MINGW,
            "-shared",
            "-O2",
            "-Wl,--no-insert-timestamp",
            "-Wall",
            "-Wextra",
            "-Werror",
            "-o",
            str(DLL),
            str(BRIDGE_SRC),
            "-ladvapi32",
        ]
    )
    if DLL.read_bytes()[:2] != b"MZ":
        sys.exit("built DLL is not a PE file")


def stage():
    if STAGE.exists():
        shutil.rmtree(STAGE)
    mod = STAGE / "SandboxToolbox"
    shutil.copytree(MOD_SRC, mod)
    (mod / "Scripts" / "native").mkdir()
    shutil.copy2(DLL, mod / "Scripts" / "native" / "native_bridge.dll")
    shutil.copy2(LICENSE, mod / "LICENSE")
    shutil.copytree(VENDOR, STAGE / "shared" / "ModMenu")


def write_zip(path, roots):
    files = []
    for top in roots:
        base = STAGE / top
        files += [p for p in sorted(base.rglob("*")) if p.is_file()]
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            info = zipfile.ZipInfo(p.relative_to(STAGE).as_posix(), ZIP_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, p.read_bytes())
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    print(
        f"{path.relative_to(ROOT)}  {path.stat().st_size // 1024} KiB  sha256 {digest[:16]}..."
    )


def main():
    ap = argparse.ArgumentParser(
        description="Build the distributable Sandbox Toolbox zip."
    )
    ap.add_argument(
        "--prebuilt",
        action="store_true",
        help="skip lint and the DLL build (make has done them)",
    )
    args = ap.parse_args()

    v = version()
    if args.prebuilt:
        if not DLL.is_file():
            sys.exit(f"--prebuilt: {DLL.relative_to(ROOT)} is missing")
    else:
        lint()
        build_dll()
    stage()

    DIST.mkdir(exist_ok=True)
    for old in DIST.glob("SandboxToolbox-*.zip"):
        old.unlink()
    write_zip(DIST / f"SandboxToolbox-{v}.zip", ["SandboxToolbox", "shared"])

if __name__ == "__main__":
    main()
