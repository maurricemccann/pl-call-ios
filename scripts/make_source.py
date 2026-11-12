#!/usr/bin/env python3
"""Writes the SideStore source file for one build, from the built app itself.

Usage: make_source.py --app <PLCall.app> --ipa <PLCall.ipa> --repo <owner/name> --tag <release tag> --out source.json

The privacy block and the entitlement list are read from the built app (and its extensions), because
SideStore refuses an install when the source and the app disagree. Nothing private is read or written:
only public build facts. It also stops the build if a font named in Info.plist is not in the app.
"""
import argparse
import datetime
import glob
import json
import os
import plistlib
import subprocess
import sys

# Keys every signer rewrites; a source does not declare them.
IGNORED_ENTITLEMENTS = {"application-identifier", "com.apple.developer.team-identifier", "get-task-allow", "keychain-access-groups"}


def entitlements(bundle: str) -> set:
    """Entitlement keys in a bundle's signature. An unsigned bundle has none."""
    try:
        out = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", bundle], capture_output=True, timeout=60).stdout
        return set(plistlib.loads(out).keys()) - IGNORED_ENTITLEMENTS if out.strip() else set()
    except (OSError, subprocess.SubprocessError, plistlib.InvalidFileException, ValueError):
        return set()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--app", required=True)
    ap.add_argument("--ipa", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    with open(os.path.join(a.app, "Info.plist"), "rb") as f:
        info = plistlib.load(f)

    missing = [name for name in info.get("UIAppFonts", []) if not os.path.isfile(os.path.join(a.app, name))]
    if missing:
        sys.exit(f"FAIL: fonts named in Info.plist are not in the app: {missing}")

    bundles = [a.app] + sorted(glob.glob(os.path.join(a.app, "PlugIns", "*.appex")))
    privacy = {}
    ents = set()
    for bundle in bundles:
        with open(os.path.join(bundle, "Info.plist"), "rb") as f:
            plist = plistlib.load(f)
        privacy.update({k: v for k, v in plist.items() if k.endswith("UsageDescription")})
        ents |= entitlements(bundle)

    base = f"https://github.com/{a.repo}/releases/download/{a.tag}"
    version = {
        "version": info["CFBundleShortVersionString"],
        "buildVersion": str(info["CFBundleVersion"]),
        "date": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "downloadURL": f"{base}/{os.path.basename(a.ipa)}",
        "size": os.path.getsize(a.ipa),
        "minOSVersion": str(info.get("MinimumOSVersion", "26.0")),
    }
    source = {
        "name": "Call",
        "subtitle": "A native iPhone app",
        "description": "Builds of the Call app.",
        "iconURL": f"https://raw.githubusercontent.com/{a.repo}/main/assets/icon.png",
        "tintColor": "#E8641E",
        "apps": [
            {
                "name": info.get("CFBundleDisplayName", "Call"),
                "bundleIdentifier": info["CFBundleIdentifier"],
                "developerName": "Call",
                "subtitle": "Hands-free voice call",
                "localizedDescription": "A native iPhone app, built from SwiftUI.",
                "iconURL": f"https://raw.githubusercontent.com/{a.repo}/main/assets/icon.png",
                "tintColor": "#E8641E",
                "category": "utilities",
                "versions": [version],
                "appPermissions": {"entitlements": sorted(ents), "privacy": privacy},
            }
        ],
    }
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(source, f, indent=2)
    print(
        f"source.json: {version['version']} ({version['buildVersion']}), {version['size']} bytes, "
        f"{len(privacy)} privacy keys, {len(ents)} entitlements, {len(bundles) - 1} extension(s)"
    )


if __name__ == "__main__":
    main()
