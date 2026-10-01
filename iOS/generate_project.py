#!/usr/bin/env python3
"""Writes FokusWald.xcodeproj: the iPhone/iPad app plus its Live Activity widget extension.

Run again after adding or removing source files (edit the lists below):  python3 generate_project.py
"""
import hashlib
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
MAC = "../FocusForest/Sources/FocusForest"
BUNDLE_ID = "io.github.alexx161.fokuswald"

# Code shared with the Mac app lives in the Mac package and is compiled into the iOS targets as well.
SHARED_APP = ["Theme", "Species", "PlantPainter", "IslandPainter", "Core", "Components", "IslandView",
              "OverviewViews", "Onboarding"]
SHARED_WIDGET = ["Theme", "Species", "PlantPainter"]
APP_SOURCES = ["FokusWald/FokusWaldApp.swift", "FokusWald/AppModel.swift", "FokusWald/TimerScreen.swift"]
BOTH_SOURCES = ["Shared/FocusActivityAttributes.swift"]
WIDGET_SOURCES = ["Widgets/FokusWaldWidgets.swift"]


def uid(name):
    return hashlib.md5(name.encode()).hexdigest()[:24].upper()


def quote(value):
    return value if re.fullmatch(r"[A-Za-z0-9_./]+", value) else '"' + value.replace('"', '\\"') + '"'


def dump(value, indent=1):
    tabs = "\t" * indent
    if isinstance(value, dict):
        body = "".join(f"{tabs}\t{quote(k)} = {dump(v, indent + 1)};\n" for k, v in value.items())
        return "{\n" + body + tabs + "}"
    if isinstance(value, list):
        return "(\n" + "".join(f"{tabs}\t{dump(v, indent + 1)},\n" for v in value) + tabs + ")"
    return quote(str(value))


objects = {}
shared_paths = {name: f"{MAC}/{name}.swift" for name in set(SHARED_APP + SHARED_WIDGET)}


def file_ref(path, kind="sourcecode.swift"):
    ref = uid("ref:" + path)
    objects[ref] = {"isa": "PBXFileReference", "lastKnownFileType": kind, "name": os.path.basename(path),
                    "path": path, "sourceTree": "SOURCE_ROOT"}
    return ref


def build_file(target, ref, extra=None):
    bid = uid(f"build:{target}:{ref}")
    objects[bid] = {"isa": "PBXBuildFile", "fileRef": ref, **(extra or {})}
    return bid


shared_refs = {name: file_ref(path) for name, path in sorted(shared_paths.items())}
local_refs = {path: file_ref(path) for path in APP_SOURCES + BOTH_SOURCES + WIDGET_SOURCES}
assets_ref = file_ref("FokusWald/Assets.xcassets", "folder.assetcatalog")
plist_refs = [file_ref("FokusWald/Info.plist", "text.plist.xml"), file_ref("Widgets/Info.plist", "text.plist.xml")]

app_product, widget_product = uid("product:app"), uid("product:widget")
objects[app_product] = {"isa": "PBXFileReference", "explicitFileType": "wrapper.application", "includeInIndex": 0,
                        "path": "FokusWald.app", "sourceTree": "BUILT_PRODUCTS_DIR"}
objects[widget_product] = {"isa": "PBXFileReference", "explicitFileType": "wrapper.app-extension", "includeInIndex": 0,
                           "path": "FokusWaldWidgets.appex", "sourceTree": "BUILT_PRODUCTS_DIR"}


def phase(key, isa, files, **extra):
    pid = uid("phase:" + key)
    objects[pid] = {"isa": isa, "buildActionMask": 2147483647, "files": files,
                    "runOnlyForDeploymentPostprocessing": 0, **extra}
    return pid


app_sources = phase("app:sources", "PBXSourcesBuildPhase",
                    [build_file("app", shared_refs[n]) for n in SHARED_APP]
                    + [build_file("app", local_refs[p]) for p in APP_SOURCES + BOTH_SOURCES])
app_frameworks = phase("app:frameworks", "PBXFrameworksBuildPhase", [])
app_resources = phase("app:resources", "PBXResourcesBuildPhase", [build_file("app", assets_ref)])
app_embed = phase("app:embed", "PBXCopyFilesBuildPhase",
                  [build_file("app", widget_product, {"settings": {"ATTRIBUTES": ["RemoveHeadersOnCopy"]}})],
                  dstPath="", dstSubfolderSpec=13, name="Embed Foundation Extensions")
widget_sources = phase("widget:sources", "PBXSourcesBuildPhase",
                       [build_file("widget", shared_refs[n]) for n in SHARED_WIDGET]
                       + [build_file("widget", local_refs[p]) for p in BOTH_SOURCES + WIDGET_SOURCES])
widget_frameworks = phase("widget:frameworks", "PBXFrameworksBuildPhase", [])
widget_resources = phase("widget:resources", "PBXResourcesBuildPhase", [])

project, app_target, widget_target = uid("project"), uid("target:app"), uid("target:widget")


def config_list(name, debug, release):
    ids = []
    for label, settings in (("Debug", debug), ("Release", release)):
        cid = uid(f"config:{name}:{label}")
        objects[cid] = {"isa": "XCBuildConfiguration", "buildSettings": settings, "name": label}
        ids.append(cid)
    lid = uid("configlist:" + name)
    objects[lid] = {"isa": "XCConfigurationList", "buildConfigurations": ids,
                    "defaultConfigurationIsVisible": 0, "defaultConfigurationName": "Release"}
    return lid


common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0", "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2", "MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1",
    "CODE_SIGN_STYLE": "Automatic", "GENERATE_INFOPLIST_FILE": "YES", "SWIFT_EMIT_LOC_STRINGS": "NO",
}
project_debug = {**common, "COPY_PHASE_STRIP": "NO", "DEBUG_INFORMATION_FORMAT": "dwarf", "ENABLE_TESTABILITY": "YES",
                 "GCC_OPTIMIZATION_LEVEL": "0", "ONLY_ACTIVE_ARCH": "YES",
                 "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG", "SWIFT_OPTIMIZATION_LEVEL": "-Onone"}
project_release = {**common, "COPY_PHASE_STRIP": "NO", "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                   "SWIFT_COMPILATION_MODE": "wholemodule", "SWIFT_OPTIMIZATION_LEVEL": "-O", "VALIDATE_PRODUCT": "YES"}

orientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight"
app_settings = {
    "PRODUCT_NAME": "FokusWald", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID,
    "INFOPLIST_FILE": "FokusWald/Info.plist", "INFOPLIST_KEY_CFBundleDisplayName": "Fokus-Wald",
    "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.productivity",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES", "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": orientations,
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": orientations + " UIInterfaceOrientationPortraitUpsideDown",
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks",
}
widget_settings = {
    "PRODUCT_NAME": "FokusWaldWidgets", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE_ID + ".widgets",
    "INFOPLIST_FILE": "Widgets/Info.plist", "INFOPLIST_KEY_CFBundleDisplayName": "Fokus-Wald",
    "SKIP_INSTALL": "YES", "APPLICATION_EXTENSION_API_ONLY": "YES",
    "LD_RUNPATH_SEARCH_PATHS": "$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks",
}

proxy, dependency = uid("proxy:widget"), uid("dependency:widget")
objects[proxy] = {"isa": "PBXContainerItemProxy", "containerPortal": project, "proxyType": 1,
                  "remoteGlobalIDString": widget_target, "remoteInfo": "FokusWaldWidgets"}
objects[dependency] = {"isa": "PBXTargetDependency", "target": widget_target, "targetProxy": proxy}

objects[app_target] = {
    "isa": "PBXNativeTarget", "buildConfigurationList": config_list("app", app_settings, app_settings),
    "buildPhases": [app_sources, app_frameworks, app_resources, app_embed], "buildRules": [],
    "dependencies": [dependency], "name": "FokusWald", "productName": "FokusWald",
    "productReference": app_product, "productType": "com.apple.product-type.application",
}
objects[widget_target] = {
    "isa": "PBXNativeTarget", "buildConfigurationList": config_list("widget", widget_settings, widget_settings),
    "buildPhases": [widget_sources, widget_frameworks, widget_resources], "buildRules": [], "dependencies": [],
    "name": "FokusWaldWidgets", "productName": "FokusWaldWidgets",
    "productReference": widget_product, "productType": "com.apple.product-type.app-extension",
}


def group(name, children):
    gid = uid("group:" + name)
    objects[gid] = {"isa": "PBXGroup", "children": children, "name": name, "sourceTree": "<group>"}
    return gid


products_group = group("Products", [app_product, widget_product])
main_group = group("FokusWald", [
    group("Gemeinsam mit Mac-App", list(shared_refs.values())),
    group("App", [local_refs[p] for p in APP_SOURCES] + [assets_ref, plist_refs[0]]),
    group("Live-Anzeige", [local_refs[p] for p in BOTH_SOURCES + WIDGET_SOURCES] + [plist_refs[1]]),
    products_group,
])

objects[project] = {
    "isa": "PBXProject",
    "attributes": {"BuildIndependentTargetsInParallel": 1, "LastSwiftUpdateCheck": 2700, "LastUpgradeCheck": 2700,
                   "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "27.0"},
                                        widget_target: {"CreatedOnToolsVersion": "27.0"}}},
    "buildConfigurationList": config_list("project", project_debug, project_release),
    "compatibilityVersion": "Xcode 14.0", "developmentRegion": "de", "hasScannedForEncodings": 0,
    "knownRegions": ["de", "Base", "en"], "mainGroup": main_group, "productRefGroup": products_group,
    "projectDirPath": "", "projectRoot": "", "targets": [app_target, widget_target],
}

body = "".join(f"\t\t{key} = {dump(value, 2)};\n" for key, value in sorted(objects.items()))
text = ("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n"
        + body + "\t};\n\trootObject = " + project + ";\n}\n")

out = os.path.join(HERE, "FokusWald.xcodeproj")
os.makedirs(out, exist_ok=True)
with open(os.path.join(out, "project.pbxproj"), "w") as f:
    f.write(text)
print("Geschrieben:", os.path.join(out, "project.pbxproj"))
