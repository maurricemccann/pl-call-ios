#!/usr/bin/env python3
"""Structural check of the hand-written Xcode project file. Nobody can open it in Xcode here, so this
parses it and fails loudly on anything Xcode would choke on or quietly drop.

Usage: python3 scripts/check_pbxproj.py [path/to/project.pbxproj]
Checks: the file parses; braces and brackets balance; every object id is defined once; every id that is
referenced exists; each target has its build phases, configurations, product and synchronized folders;
every folder and Info.plist the project names exists on disk.
"""
import os
import re
import sys

ID = re.compile(r"^[0-9A-F]{24}$")
TOKEN = re.compile(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,"]+', re.S)


def tokens(text):
    for m in TOKEN.finditer(text):
        t = m.group(0)
        if not (t.startswith("/*") or t.startswith("//")):
            yield t


class Parser:
    """The old-style property list Xcode writes: dictionaries in braces, lists in brackets."""

    def __init__(self, text):
        self.t = list(tokens(text))
        self.i = 0
        self.dupes = []

    def take(self, want=None):
        if self.i >= len(self.t):
            raise SystemExit(f"FAIL: the file ends early (wanted {want!r})")
        tok = self.t[self.i]
        self.i += 1
        if want is not None and tok != want:
            raise SystemExit(f"FAIL: expected {want!r} but found {tok!r} near token {self.i}: {' '.join(self.t[max(0, self.i - 6):self.i + 3])}")
        return tok

    def value(self):
        tok = self.take()
        if tok == "{":
            d = {}
            while self.t[self.i] != "}":
                key = self.take().strip('"')
                self.take("=")
                val = self.value()
                self.take(";")
                if key in d:
                    self.dupes.append(key)
                d[key] = val
            self.take("}")
            return d
        if tok == "(":
            items = []
            while self.t[self.i] != ")":
                items.append(self.value())
                if self.t[self.i] == ",":
                    self.take(",")
            self.take(")")
            return items
        if tok in "})=;,":
            raise SystemExit(f"FAIL: unexpected {tok!r} near token {self.i}")
        return tok[1:-1] if tok.startswith('"') else tok


def ids_in(value):
    if isinstance(value, dict):
        for k, v in value.items():
            if ID.match(k):
                yield k
            yield from ids_in(v)
    elif isinstance(value, list):
        for v in value:
            yield from ids_in(v)
    elif ID.match(value):
        yield value


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "PLCall.xcodeproj", "project.pbxproj")
    root_dir = os.path.abspath(os.path.join(os.path.dirname(path), ".."))
    text = open(path, encoding="utf-8").read()
    errors = []

    def need(ok, message):
        if not ok:
            errors.append(message)

    need(text.startswith("// !$*UTF8*$!"), "the first line must be the UTF8 marker")
    bare = re.sub(r'/\*.*?\*/|"(?:\\.|[^"\\])*"', "", text, flags=re.S)
    need(bare.count("{") == bare.count("}"), f"braces do not balance: {bare.count('{')} open, {bare.count('}')} close")
    need(bare.count("(") == bare.count(")"), f"brackets do not balance: {bare.count('(')} open, {bare.count(')')} close")

    p = Parser(text)
    proj = p.value()
    need(p.i == len(p.t), "there is text after the closing brace")
    need(not p.dupes, f"keys defined more than once: {p.dupes}")
    objects = proj.get("objects", {})
    need(proj.get("objectVersion") == "77", f"objectVersion is {proj.get('objectVersion')}, synchronized folders need 77")

    # every id defined exactly once (the parser would hide a repeat, so count in the raw text too)
    defined = re.findall(r"^\t\t([0-9A-F]{24})(?: /\*.*?\*/)? = \{", text, flags=re.M)
    for oid in sorted(set(defined)):
        need(defined.count(oid) == 1, f"object {oid} is defined {defined.count(oid)} times")
    need(set(defined) == set(objects), "the objects found by the parser and by the line scan differ")
    for oid, obj in objects.items():
        need(ID.match(oid) is not None, f"object id {oid!r} is not 24 hex characters")
        need(isinstance(obj, dict) and "isa" in obj, f"object {oid} has no isa")

    # every id that is referenced exists
    referenced = set(ids_in({k: v for k, v in proj.items() if k != "objects"}))
    for obj in objects.values():
        referenced |= set(ids_in(obj))
    for oid in sorted(referenced - set(objects)):
        errors.append(f"id {oid} is referenced but never defined")
    for oid in sorted(set(objects) - referenced):
        errors.append(f"object {oid} ({objects[oid].get('isa')}) is defined but nothing refers to it")

    def isa(oid):
        return objects.get(oid, {}).get("isa")

    project = objects.get(proj.get("rootObject"), {})
    need(project.get("isa") == "PBXProject", "rootObject is not a PBXProject")
    need(isa(project.get("mainGroup")) == "PBXGroup", "mainGroup is not a PBXGroup")

    def configs_ok(list_id, owner):
        lst = objects.get(list_id, {})
        need(lst.get("isa") == "XCConfigurationList", f"{owner}: no configuration list")
        names = [objects.get(c, {}).get("name") for c in lst.get("buildConfigurations", [])]
        need(sorted(names) == ["Debug", "Release"], f"{owner}: configurations are {names}, want Debug and Release")
        need(lst.get("defaultConfigurationName") in names, f"{owner}: the default configuration is not in the list")
        return [objects.get(c, {}).get("buildSettings", {}) for c in lst.get("buildConfigurations", [])]

    for settings in configs_ok(project.get("buildConfigurationList"), "project"):
        need(settings.get("SWIFT_VERSION") == "6.0", "project: SWIFT_VERSION must be 6.0")
        need(settings.get("IPHONEOS_DEPLOYMENT_TARGET") == "26.0", "project: IPHONEOS_DEPLOYMENT_TARGET must be 26.0")
        need(settings.get("SWIFT_DEFAULT_ACTOR_ISOLATION") == "nonisolated", "project: default actor isolation must stay nonisolated")
        need(settings.get("TARGETED_DEVICE_FAMILY") == "1", "project: iPhone only")

    # where each synchronized folder sits on disk, found by walking the group tree
    folder_path = {}

    def walk(gid, base):
        g = objects.get(gid, {})
        here = os.path.join(base, g.get("path", "")) if g.get("isa") in ("PBXGroup", "PBXFileSystemSynchronizedRootGroup") else base
        if g.get("isa") == "PBXFileSystemSynchronizedRootGroup":
            folder_path[gid] = here
        for child in g.get("children", []):
            walk(child, here)

    walk(project.get("mainGroup"), root_dir)

    want = {
        "PLCall": ("com.apple.product-type.application", {"PLCall", "Shared", "PLCallCore/Sources/PLCallCore"}),
        "PLCallWidgets": ("com.apple.product-type.app-extension", {"PLCallWidgets", "Shared", "PLCallCore/Sources/PLCallCore"}),
    }
    targets = {objects[t].get("name"): (t, objects[t]) for t in project.get("targets", []) if t in objects}
    need(set(want) <= set(targets) <= set(want) | {"PLCallWatch"}, f"targets are {sorted(targets)}, want {sorted(want)} (PLCallWatch is optional)")
    for name, (tid, target) in targets.items():
        if name not in want:
            continue
        product_type, folders = want[name]
        need(target.get("isa") == "PBXNativeTarget", f"{name}: not a PBXNativeTarget")
        need(target.get("productType") == product_type, f"{name}: productType is {target.get('productType')}")
        phases = [isa(ph) for ph in target.get("buildPhases", [])]
        for phase in ("PBXSourcesBuildPhase", "PBXFrameworksBuildPhase", "PBXResourcesBuildPhase"):
            need(phases.count(phase) == 1, f"{name}: needs exactly one {phase}, has {phases.count(phase)}")
        need(isa(target.get("productReference")) == "PBXFileReference", f"{name}: no product reference")
        got = {os.path.relpath(folder_path[g], root_dir).replace(os.sep, "/") for g in target.get("fileSystemSynchronizedGroups", []) if g in folder_path}
        need(got == folders, f"{name}: synchronized folders are {sorted(got)}, want {sorted(folders)}")
        for settings in configs_ok(target.get("buildConfigurationList"), name):
            need(settings.get("GENERATE_INFOPLIST_FILE") == "YES", f"{name}: GENERATE_INFOPLIST_FILE must be YES")
            plist = settings.get("INFOPLIST_FILE", "")
            need(os.path.isfile(os.path.join(root_dir, plist)), f"{name}: INFOPLIST_FILE {plist!r} is not on disk")
            need(settings.get("PRODUCT_BUNDLE_IDENTIFIER", "").startswith("com.psychedluxuries.call"), f"{name}: bundle id")
            need("SWIFT_DEFAULT_ACTOR_ISOLATION" not in settings, f"{name}: do not override the default actor isolation per target")
            if name == "PLCallWidgets":
                need(settings.get("SKIP_INSTALL") == "YES", "PLCallWidgets: SKIP_INSTALL must be YES")
                need(settings.get("PRODUCT_BUNDLE_IDENTIFIER") == "com.psychedluxuries.call.widgets", "PLCallWidgets: the bundle id must sit under the app's")
                need("@executable_path/../../Frameworks" in settings.get("LD_RUNPATH_SEARCH_PATHS", []), "PLCallWidgets: runpath")
            else:
                need(settings.get("ASSETCATALOG_COMPILER_APPICON_NAME") == "AppIcon", "PLCall: app icon name")

    # the app embeds the extension and depends on it
    if set(want) <= set(targets):
        app_id, app = targets["PLCall"]
        ext_id, ext = targets["PLCallWidgets"]
        embeds = [objects[ph] for ph in app.get("buildPhases", []) if isa(ph) == "PBXCopyFilesBuildPhase"]
        need(len(embeds) == 1 and embeds[0].get("dstSubfolderSpec") == "13", "PLCall: needs one Embed Foundation Extensions phase (dstSubfolderSpec 13)")
        embedded = [objects.get(f, {}).get("fileRef") for e in embeds for f in e.get("files", [])]
        need(embedded == [ext.get("productReference")], "PLCall: the embed phase must hold the extension product")
        deps = [objects.get(d, {}) for d in app.get("dependencies", [])]
        need([d.get("target") for d in deps] == [ext_id], "PLCall: must depend on PLCallWidgets")
        for d in deps:
            proxy = objects.get(d.get("targetProxy"), {})
            need(proxy.get("remoteGlobalIDString") == ext_id and proxy.get("containerPortal") == proj.get("rootObject"), "PLCall: the dependency proxy does not point at the extension")

    # folders exist; each Info.plist inside a synchronized folder is kept out of the bundle's resources
    for gid, where in folder_path.items():
        need(os.path.isdir(where), f"synchronized folder {os.path.relpath(where, root_dir)} is not on disk")
        owners = [tid for _, (tid, t) in targets.items() if gid in t.get("fileSystemSynchronizedGroups", [])]
        sets = [objects.get(e, {}) for e in objects[gid].get("exceptions", [])]
        for s in sets:
            need(s.get("isa") == "PBXFileSystemSynchronizedBuildFileExceptionSet", "an exception is not an exception set")
            need(isa(s.get("target")) == "PBXNativeTarget", "an exception set has no target")
            for rel in s.get("membershipExceptions", []):
                need(os.path.isfile(os.path.join(where, rel)), f"exception {rel!r} is not a file in {os.path.relpath(where, root_dir)}")
        if os.path.isfile(os.path.join(where, "Info.plist")):
            for tid in owners:
                excluded = any(s.get("target") == tid and "Info.plist" in s.get("membershipExceptions", []) for s in sets)
                need(excluded, f"{os.path.relpath(where, root_dir)}/Info.plist would be copied as a resource (no exception for target {objects[tid].get('name')})")

    kinds = {}
    for obj in objects.values():
        kinds[obj.get("isa")] = kinds.get(obj.get("isa"), 0) + 1
    print(f"{os.path.relpath(path, root_dir)}: {len(objects)} objects, {len(referenced)} ids referenced")
    for kind in sorted(kinds):
        print(f"  {kinds[kind]:2d}  {kind}")
    for name, (tid, target) in sorted(targets.items()):
        print(f"  target {name}: phases {[isa(ph)[3:-10] for ph in target.get('buildPhases', [])]}")
    if errors:
        print(f"FAILED: {len(errors)} problem(s)")
        for e in errors:
            print("  -", e)
        sys.exit(1)
    print("PBXPROJ OK")


if __name__ == "__main__":
    main()
