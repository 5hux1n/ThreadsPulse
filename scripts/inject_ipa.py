#!/usr/bin/env python3
import argparse
import os
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile

DYLIB_LOAD_PATH = "@executable_path/Frameworks/ThreadsPulse.dylib"

MH_MAGIC_64 = 0xFEEDFACF
FAT_MAGIC = 0xCAFEBABE
FAT_MAGIC_64 = 0xCAFEBABF
LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0x0C
LC_LOAD_WEAK_DYLIB = 0x80000018
LC_ENCRYPTION_INFO_64 = 0x2C
ZEROFILL_TYPES = (0x1, 0xC, 0x12)

def fail(msg):
    print(f"::error::{msg}" if os.environ.get("GITHUB_ACTIONS") else f"Error: {msg}", file=sys.stderr)
    sys.exit(1)

def patch_slice(buf, off, load_path):
    if struct.unpack_from("<I", buf, off)[0] != MH_MAGIC_64:
        fail("Only 64-bit (arm64) executables are supported")
    ncmds, sizeofcmds = struct.unpack_from("<II", buf, off + 16)
    header_size = 32
    p = off + header_size
    first_data = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", buf, p)
        if cmd in (LC_LOAD_DYLIB, LC_LOAD_WEAK_DYLIB):
            name_off = struct.unpack_from("<I", buf, p + 8)[0]
            name = bytes(buf[p + name_off:p + cmdsize]).split(b"\0")[0].decode(errors="replace")
            if name == load_path:
                return False
        elif cmd == LC_ENCRYPTION_INFO_64:
            cryptid = struct.unpack_from("<I", buf, p + 16)[0]
            if cryptid != 0:
                fail("This IPA is not decrypted (App Store encryption). Use a decrypted Threads IPA")
        elif cmd == LC_SEGMENT_64:
            nsects = struct.unpack_from("<I", buf, p + 64)[0]
            for i in range(nsects):
                s = p + 72 + i * 80
                sec_off = struct.unpack_from("<I", buf, s + 48)[0]
                sec_type = struct.unpack_from("<I", buf, s + 64)[0] & 0xFF
                if sec_off and sec_type not in ZEROFILL_TYPES:
                    first_data = sec_off if first_data is None else min(first_data, sec_off)
        p += cmdsize

    name = load_path.encode() + b"\0"
    size = (24 + len(name) + 7) & ~7
    end = off + header_size + sizeofcmds
    if first_data is None:
        fail("Could not find where the code starts, so the free header space is unknown")
    if end + size > off + first_data:
        fail(f"Not enough header space in the executable ({size} bytes needed)")
    if any(buf[end:end + size]):
        fail("The space after the executable header is not empty, so the load command cannot be added safely")

    command = struct.pack("<IIIIII", LC_LOAD_DYLIB, size, 24, 2, 0x10000, 0x10000) + name
    buf[end:end + size] = command + b"\0" * (size - len(command))
    struct.pack_into("<II", buf, off + 16, ncmds + 1, sizeofcmds + size)
    return True

def patch_binary(path, load_path):
    with open(path, "rb") as f:
        buf = bytearray(f.read())
    magic = struct.unpack_from(">I", buf, 0)[0]
    changed = False
    if magic in (FAT_MAGIC, FAT_MAGIC_64):
        nfat = struct.unpack_from(">I", buf, 4)[0]
        for i in range(nfat):
            if magic == FAT_MAGIC:
                _, _, offset, _, _ = struct.unpack_from(">iiIII", buf, 8 + i * 20)
            else:
                _, _, offset, _, _, _ = struct.unpack_from(">iiQQII", buf, 8 + i * 32)
            changed |= patch_slice(buf, offset, load_path)
    else:
        changed = patch_slice(buf, 0, load_path)
    if changed:
        with open(path, "wb") as f:
            f.write(buf)
    return changed

def main():
    ap = argparse.ArgumentParser(description="Inject ThreadsPulse into a decrypted Threads IPA")
    ap.add_argument("-i", "--ipa", required=True, help="Decrypted Threads IPA")
    ap.add_argument("-d", "--dylib", required=True, help="ThreadsPulse.dylib")
    ap.add_argument("-b", "--bundle", help="Optional ThreadsPulse.bundle folder for older dylib builds")
    ap.add_argument("-o", "--output", required=True, help="Output IPA")
    ap.add_argument("--no-plugins", action="store_true",
                    help="Remove all extensions (widgets, share, etc.), for SideStore / AltStore free accounts")
    ap.add_argument("--appex", action="append", default=[], metavar="PATH",
                    help="Add an extension (.appex folder); can be repeated")
    ap.add_argument("--github-output", help="Write the Threads version to this file (for GitHub Actions)")
    args = ap.parse_args()

    for tool in ("zip", "unzip"):
        if not shutil.which(tool):
            fail(f"{tool} command not found")

    work = tempfile.mkdtemp(prefix="tp-ipa-")
    try:
        r = subprocess.run(["unzip", "-q", os.path.abspath(args.ipa), "-d", work])
        if r.returncode not in (0, 1):
            fail("Could not unzip the IPA; the file may not be an IPA")
        payload = os.path.join(work, "Payload")
        apps = [d for d in os.listdir(payload) if d.endswith(".app")] if os.path.isdir(payload) else []
        if len(apps) != 1:
            fail("No Payload/*.app found in the IPA")
        app = os.path.join(payload, apps[0])

        with open(os.path.join(app, "Info.plist"), "rb") as f:
            info = plistlib.load(f)
        bundle_id = info.get("CFBundleIdentifier", "")
        threads_version = info.get("CFBundleShortVersionString", "unknown")
        if bundle_id != "com.burbn.barcelona":
            print(f"::warning::This IPA's bundle ID is {bundle_id}, not Threads (com.burbn.barcelona)")
        print(f"Threads {threads_version} ({bundle_id})")

        frameworks = os.path.join(app, "Frameworks")
        os.makedirs(frameworks, exist_ok=True)
        shutil.copy2(args.dylib, os.path.join(frameworks, "ThreadsPulse.dylib"))
        if args.bundle:
            dst_bundle = os.path.join(app, "ThreadsPulse.bundle")
            shutil.rmtree(dst_bundle, ignore_errors=True)
            shutil.copytree(args.bundle, dst_bundle)

        exe = os.path.join(app, info["CFBundleExecutable"])
        if patch_binary(exe, DYLIB_LOAD_PATH):
            print(f"Added load command: {DYLIB_LOAD_PATH}")
        else:
            print("The executable already loads ThreadsPulse; skipped")

        if args.no_plugins:
            if args.appex:
                fail("--no-plugins and --appex can't be used together")
            for sub in ("PlugIns", "Extensions", "Watch"):
                shutil.rmtree(os.path.join(app, sub), ignore_errors=True)
            print("Removed all extensions (noplugins)")
        for appex in args.appex:
            appex = appex.rstrip("/")
            if not appex.endswith(".appex") or not os.path.isfile(os.path.join(appex, "Info.plist")):
                fail(f"Not a valid extension: {appex}")
            plugins = os.path.join(app, "PlugIns")
            os.makedirs(plugins, exist_ok=True)
            dst = os.path.join(plugins, os.path.basename(appex))
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(appex, dst, symlinks=True)
            for junk in ("embedded.mobileprovision", "_CodeSignature"):
                path = os.path.join(dst, junk)
                if os.path.isdir(path): shutil.rmtree(path)
                elif os.path.exists(path): os.remove(path)
            print(f"Added extension: {os.path.basename(appex)}")

        out = os.path.abspath(args.output)
        if os.path.exists(out):
            os.remove(out)
        subprocess.run(["zip", "-qry", out, "Payload"], cwd=work, check=True)
        print(f"Done: {out}")

        if args.github_output:
            with open(args.github_output, "a") as f:
                f.write(f"threads_version={threads_version}\n")
    finally:
        shutil.rmtree(work, ignore_errors=True)

if __name__ == "__main__":
    main()
