#!/usr/bin/env python3
"""Writes the SideStore source file for one build, from the built app's own Info.plist.

Usage: make_source.py --app <PLCall.app> --ipa <PLCall.ipa> --repo <owner/name> --tag <release tag> --out source.json

The privacy block is read from the app, because SideStore refuses an install when the source and the
app disagree. Nothing private is read or written: only public build facts.
"""
import argparse
import datetime
import json
import os
import plistlib


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

    privacy = {k: v for k, v in info.items() if k.endswith("UsageDescription")}
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
                "appPermissions": {"entitlements": [], "privacy": privacy},
            }
        ],
    }
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(source, f, indent=2)
    print(f"source.json: {version['version']} ({version['buildVersion']}), {version['size']} bytes, {len(privacy)} privacy keys")


if __name__ == "__main__":
    main()
