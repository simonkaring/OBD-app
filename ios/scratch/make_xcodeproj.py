#!/usr/bin/env python3
"""Generate VoltLink.xcodeproj from the source tree.

The project is generated (not hand-edited) because `scratch/repack_ipa.sh` rebuilds it
before every archive. Keep this script in sync with the app target's build settings,
resources, and test targets.

    python3 scratch/make_xcodeproj.py
    python3 scratch/make_xcodeproj.py --local-signing   # free / personal team
"""

import hashlib
import os
import pathlib
import sys

# A free "Personal Team" Apple ID cannot provision App Groups or the CarPlay
# Driving Task entitlement, so device builds fail to sign. `--local-signing`
# leaves both entitlement files out of the app and widget targets: the app then
# installs on a personal team, CarPlay stays inert, and `SharedTelemetryStore`
# falls back to `UserDefaults.standard` (the widget shows placeholder data).
LOCAL_SIGNING = "--local-signing" in sys.argv[1:]

# Every path below is relative to the ios/ project root, so run from there no
# matter which directory the caller invoked the script from.
os.chdir(pathlib.Path(__file__).resolve().parents[1])

PROJECT = "VoltLink"
BUNDLE_ID = "com.simonkaring.voltlink"
UI_TEST_BUNDLE_ID = BUNDLE_ID + ".uitests"

APP_DIRS = ["App", "CarPlay", "Core", "Data", "Services", "UI"]
UI_TEST_DIR = "UITests"
SOURCE_EXTENSIONS = {".swift"}
RESOURCE_EXTENSIONS = {".json", ".xcprivacy", ".xcstrings"}
ASSET_EXTENSION = ".xcassets"
EXCLUDED_FILES = {
    "App/Info.plist",
    "App/VoltLink.entitlements",
}


def gid(*role):
    """Stable 24-hex object ID derived from the object's role.

    Xcode only requires IDs to be unique inside the file. Deriving them from a role
    string instead of `uuid4()` keeps regeneration reviewable: random IDs rewrite all
    ~1,100 lines on every run, so a one-line generator change shows up as an
    unmergeable thousand-line diff.
    """
    seed = "|".join(role)
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()[:24].upper()


def gather_files(directories):
    """Return (sources, resources, asset_catalogs) relative POSIX paths."""
    sources, resources, catalogs = [], [], []
    for directory in directories:
        for root, dirs, filenames in os.walk(directory):
            if root.endswith(ASSET_EXTENSION) or ASSET_EXTENSION + "/" in root:
                continue
            for name in sorted(filenames):
                path = os.path.join(root, name).replace(os.sep, "/")
                if path in EXCLUDED_FILES:
                    continue
                ext = os.path.splitext(name)[1]
                if ext in SOURCE_EXTENSIONS:
                    sources.append(path)
                elif ext in RESOURCE_EXTENSIONS:
                    resources.append(path)
            for name in sorted(dirs):
                if name.endswith(ASSET_EXTENSION):
                    catalogs.append(os.path.join(root, name).replace(os.sep, "/"))
    return sorted(sources), sorted(resources), sorted(catalogs)


WIDGET_DIR = "Widgets"
# Activity attributes and the app-group snapshot store compile into both the app and
# the widget extension; everything under Widgets/ is extension-only.
SHARED_WIDGET_DIRS = ["Core/Sharing"]

app_sources, app_resources, app_catalogs = gather_files(APP_DIRS)
ui_sources, ui_resources, ui_catalogs = gather_files([UI_TEST_DIR])
widget_sources, widget_resources, widget_catalogs = gather_files([WIDGET_DIR] + SHARED_WIDGET_DIRS)
widget_sources = sorted(set(widget_sources))
widget_bfs = {path: gid("buildfile:widget", path) for path in widget_sources}
widget_only_sources = [path for path in widget_sources if path not in app_sources]


def file_type_for(path):
    name = os.path.basename(path)
    ext = os.path.splitext(name)[1]
    if ext == ".swift":
        return "sourcecode.swift"
    if ext == ".xcstrings":
        # String catalogs must use their own file type so Xcode compiles them to
        # per-language .lproj/Localizable.strings instead of copying the JSON.
        return "text.json.xcstrings"
    if ext == ".json":
        return "text.json"
    if ext == ".xcprivacy":
        return "text.xml"
    if ext == ASSET_EXTENSION:
        return "folder.assetcatalog"
    return "text"


ids = {}


def ids_for(path):
    if path not in ids:
        ids[path] = (gid("fileref", path), gid("buildfile", path))
    return ids[path]


# ---- Groups -----------------------------------------------------------------

main_group = gid("group:main")
products_group = gid("group:products")
groups = {".": main_group}
group_parent = {}
group_name = {}


def ensure_group(directory):
    directory = directory.replace(os.sep, "/") or "."
    if directory in groups:
        return groups[directory]
    parent = os.path.dirname(directory) or "."
    ensure_group(parent)
    group_id = gid("group", directory)
    groups[directory] = group_id
    group_parent[directory] = parent
    group_name[directory] = os.path.basename(directory)
    return group_id


group_children = {}


def add_to_group(path, child_id):
    directory = os.path.dirname(path) or "."
    group_id = ensure_group(directory)
    group_children.setdefault(group_id, []).append(child_id)


# Asset catalogs are regular `folder.assetcatalog` file references, not groups.
for path in app_sources + app_resources + app_catalogs + ui_sources + ui_resources + ui_catalogs + widget_only_sources:
    add_to_group(path, ids_for(path)[0])


def render_groups():
    lines = []
    lines.append("\t\t%s /* Main */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" % main_group)
    top = sorted([d for d in groups if d != "." and group_parent.get(d) == "."])
    children = [groups[d] for d in top] + [products_group]
    lines.append(",\n".join("\t\t\t\t%s" % c for c in children))
    lines.append("\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n")

    lines.append("\t\t%s /* Products */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" % products_group)
    lines.append("\t\t\t\t%s /* %s.app */,\n" % (app_product, PROJECT))
    lines.append("\t\t\t\t%s /* %sUITests.xctest */,\n" % (ui_product, PROJECT))
    lines.append("\t\t\t\t%s /* VoltLinkWidgets.appex */,\n" % (widget_product,))
    lines.append("\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n")

    for directory in sorted(groups):
        if directory == ".":
            continue
        lines.append("\t\t%s /* %s */ = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" % (
            groups[directory], group_name[directory]))
        kids = []
        for sub in sorted(groups):
            if sub != "." and group_parent.get(sub) == directory:
                kids.append(groups[sub])
        kids += group_children.get(groups[directory], [])
        lines.append(",\n".join("\t\t\t\t%s" % k for k in kids))
        lines.append("\n\t\t\t);\n\t\t\tpath = \"%s\";\n\t\t\tsourceTree = \"<group>\";\n\t\t};\n" % group_name[directory])
    return "".join(lines)


# ---- Targets and products ---------------------------------------------------

app_target = gid("target:app")
ui_target = gid("target:uitests")
widget_target = gid("target:widgets")
app_product = gid("product:app")
ui_product = gid("product:uitests")
widget_product = gid("product:widgets")
project_object = gid("project")

app_sources_phase = gid("phase:app:sources")
app_resources_phase = gid("phase:app:resources")
app_frameworks_phase = gid("phase:app:frameworks")
ui_sources_phase = gid("phase:uitests:sources")
ui_resources_phase = gid("phase:uitests:resources")
ui_frameworks_phase = gid("phase:uitests:frameworks")
widget_sources_phase = gid("phase:widget:sources")
widget_resources_phase = gid("phase:widget:resources")
widget_frameworks_phase = gid("phase:widget:frameworks")
widget_embed_phase = gid("phase:embed-extensions")
widget_embed_bf = gid("buildfile:widget-embed")

ui_dependency = gid("dependency:uitests")
ui_proxy = gid("proxy:uitests")
widget_dependency = gid("dependency:widgets")
widget_proxy = gid("proxy:widgets")

app_config_list = gid("configlist:app")
ui_config_list = gid("configlist:uitests")
widget_config_list = gid("configlist:widgets")
project_config_list = gid("configlist:project")

configs = {name: gid("config", name) for name in [
    "project_debug", "project_release", "app_debug", "app_release", "ui_debug", "ui_release",
    "widget_debug", "widget_release",
]}


def render_file_references():
    lines = []
    for path in app_sources + app_resources + ui_sources + ui_resources:
        fref = ids_for(path)[0]
        lines.append('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = "%s"; sourceTree = "<group>"; };\n' % (
            fref, os.path.basename(path), file_type_for(path), os.path.basename(path)))
    for path in widget_only_sources:
        fref = ids_for(path)[0]
        lines.append('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; path = "%s"; sourceTree = "<group>"; };\n' % (
            fref, os.path.basename(path), file_type_for(path), os.path.basename(path)))
    for catalog in app_catalogs + ui_catalogs:
        lines.append('\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = "%s"; sourceTree = "<group>"; };\n' % (
            ids_for(catalog)[0], os.path.basename(catalog), os.path.basename(catalog)))
    lines.append('\t\t%s /* %s.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = %s.app; sourceTree = BUILT_PRODUCTS_DIR; };\n' % (
        app_product, PROJECT, PROJECT))
    lines.append('\t\t%s /* %sUITests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = %sUITests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };\n' % (
        ui_product, PROJECT, PROJECT))
    lines.append('\t\t%s /* VoltLinkWidgets.appex */ = {isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = VoltLinkWidgets.appex; sourceTree = BUILT_PRODUCTS_DIR; };\n' % (
        widget_product,))
    return "".join(lines)


def render_phase(phase_id, name, build_file_ids):
    body = ",\n".join("\t\t\t\t%s" % b for b in build_file_ids)
    return "\t\t%s /* %s */ = {\n\t\t\tisa = PBX%sBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n" % (
        phase_id, name, "Sources" if name == "Sources" else "Resources" if name == "Resources" else "Frameworks",
        body)


# Build-file ids are consumed in order; app catalogs get their own ids.
app_source_bfs = [ids_for(p)[1] for p in app_sources]
app_resource_bfs = [ids_for(p)[1] for p in app_resources]
# Asset catalog build files are injected while rendering, so keep a stable list here.
asset_build_ids = {}
for catalog in app_catalogs:
    asset_build_ids[catalog] = gid("buildfile:catalog", catalog)
ui_source_bfs = [ids_for(p)[1] for p in ui_sources]


def render_build_files_with_assets():
    lines = []
    for path in app_sources:
        fref, bref = ids_for(path)
        lines.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (
            bref, os.path.basename(path), fref, os.path.basename(path)))
    for path in app_resources:
        fref, bref = ids_for(path)
        lines.append("\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (
            bref, os.path.basename(path), fref, os.path.basename(path)))
    for catalog in app_catalogs:
        lines.append("\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (
            asset_build_ids[catalog], os.path.basename(catalog), ids_for(catalog)[0], os.path.basename(catalog)))
    for path in ui_sources:
        fref, bref = ids_for(path)
        lines.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (
            bref, os.path.basename(path), fref, os.path.basename(path)))
    for path in widget_sources:
        lines.append("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };\n" % (
            widget_bfs[path], os.path.basename(path), ids_for(path)[0], os.path.basename(path)))
    return "".join(lines)


common_app_settings = """\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = App/VoltLink.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tINFOPLIST_FILE = App/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tLOCALIZATION_PREFERS_STRING_CATALOGS = YES;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "%s";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
""" % BUNDLE_ID

common_ui_settings = """\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@loader_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "%s";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
\t\t\t\tTEST_TARGET_NAME = %s;
""" % (UI_TEST_BUNDLE_ID, PROJECT)

common_widget_settings = """\t\t\t\tAPPLICATION_EXTENSION_API_ONLY = YES;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = Widgets/VoltLinkWidgets.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Widgets/Info.plist;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t\t"@executable_path/../../Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "com.simonkaring.voltlink.widgets";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSKIP_INSTALL = YES;
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
"""

if LOCAL_SIGNING:
    # See LOCAL_SIGNING above: personal teams cannot provision these capabilities.
    common_app_settings = common_app_settings.replace(
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = App/VoltLink.entitlements;\n", "")
    common_widget_settings = common_widget_settings.replace(
        "\t\t\t\tCODE_SIGN_ENTITLEMENTS = Widgets/VoltLinkWidgets.entitlements;\n", "")

# Xcode writes the selected team into the project, so a plain regeneration would
# drop it and automatic signing would fall back to "no team". Export
# VOLTLINK_DEVELOPMENT_TEAM=<TeamID> to carry the selection into the project.
DEVELOPMENT_TEAM = os.environ.get("VOLTLINK_DEVELOPMENT_TEAM", "").strip()


def with_development_team(settings):
    """Insert DEVELOPMENT_TEAM in alphabetical position, if one was requested."""
    if not DEVELOPMENT_TEAM:
        return settings
    line = '\t\t\t\tDEVELOPMENT_TEAM = "%s";\n' % DEVELOPMENT_TEAM
    for anchor in ("\t\t\t\tGENERATE_INFOPLIST_FILE", "\t\t\t\tINFOPLIST_FILE", "\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET"):
        if anchor in settings:
            return settings.replace(anchor, line + anchor, 1)
    return settings + line


common_app_settings = with_development_team(common_app_settings)
common_ui_settings = with_development_team(common_ui_settings)
common_widget_settings = with_development_team(common_widget_settings)

project_settings = """\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tENABLE_PREVIEWS = YES;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = NO;
\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;
\t\t\t\tMARKETING_VERSION = 1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = "%s";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
""" % BUNDLE_ID

project_file = """// !$*UTF8*$!
{
\tarchiveVersion = 1;
\tclasses = {
\t};
\tobjectVersion = 56;
\tobjects = {

/* Begin PBXBuildFile section */
%s/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t%s /* PBXContainerItemProxy */ = {
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = %s /* Project Object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = %s;
\t\t\tremoteInfo = %s;
\t\t};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
%s/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t%s /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
\t\t%s /* Frameworks */ = {
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
%s/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t%s /* %s */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%s" */;
\t\t\tbuildPhases = (
\t\t\t\t%s /* Sources */,
\t\t\t\t%s /* Resources */,
\t\t\t\t%s /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = %s;
\t\t\tproductName = %s;
\t\t\tproductReference = %s /* %s.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t};
\t\t%s /* %sUITests */ = {
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget "%sUITests" */;
\t\t\tbuildPhases = (
\t\t\t\t%s /* Sources */,
\t\t\t\t%s /* Resources */,
\t\t\t\t%s /* Frameworks */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t%s /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = %sUITests;
\t\t\tproductName = %sUITests;
\t\t\tproductReference = %s /* %sUITests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.ui-testing";
\t\t};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t%s /* Project Object */ = {
\t\t\tisa = PBXProject;
\t\t\tattributes = {
\t\t\t\tBuildIndependentTargetsInParallel = 1;
\t\t\t\tLastUpgradeCheck = 1600;
\t\t\t\tTargetAttributes = {
\t\t\t\t\t%s = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t};
\t\t\t\t\t%s = {
\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;
\t\t\t\t\t\tTestTargetID = %s;
\t\t\t\t\t};
\t\t\t\t};
\t\t\t};
\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXProject "%s" */;
\t\t\tcompatibilityVersion = "Xcode 14.0";
\t\t\tdevelopmentRegion = en;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = %s /* Main */;
\t\t\tproductRefGroup = %s /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t%s /* %s */,
\t\t\t\t%s /* %sUITests */,
\t\t\t);
\t\t};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t%s /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
%s\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
\t\t%s /* Resources */ = {
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t%s /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
%s\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
\t\t%s /* Sources */ = {
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
%s\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t%s /* PBXTargetDependency */ = {
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = %s /* %s */;
\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;
\t\t};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t%s /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
%s\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t%s /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
%s\t\t\t};
\t\t\tname = Release;
\t\t};
\t\t%s /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
%s\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t%s /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
%s\t\t\t};
\t\t\tname = Release;
\t\t};
\t\t%s /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
%s\t\t\t};
\t\t\tname = Debug;
\t\t};
\t\t%s /* Release */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
%s\t\t\t};
\t\t\tname = Release;
\t\t};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t%s /* Build configuration list for PBXProject "%s" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t%s /* Debug */,
\t\t\t\t%s /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\t%s /* Build configuration list for PBXNativeTarget "%s" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t%s /* Debug */,
\t\t\t\t%s /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
\t\t%s /* Build configuration list for PBXNativeTarget "%sUITests" */ = {
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t%s /* Debug */,
\t\t\t\t%s /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t};
/* End XCConfigurationList section */
\t};
\trootObject = %s /* Project Object */;
}
"""

app_resource_build_files = app_resource_bfs + [asset_build_ids[c] for c in app_catalogs]

content = project_file % (
    render_build_files_with_assets(),
    ui_proxy, project_object, app_target, PROJECT,
    render_file_references(),
    app_frameworks_phase, ui_frameworks_phase,
    render_groups(),
    app_target, PROJECT, app_config_list, PROJECT,
    app_sources_phase, app_resources_phase, app_frameworks_phase,
    PROJECT, PROJECT, app_product, PROJECT,
    ui_target, PROJECT, ui_config_list, PROJECT,
    ui_sources_phase, ui_resources_phase, ui_frameworks_phase,
    ui_dependency,
    PROJECT, PROJECT, ui_product, PROJECT,
    project_object,
    app_target, ui_target, app_target,
    project_config_list, PROJECT,
    main_group, products_group,
    app_target, PROJECT, ui_target, PROJECT,
    app_resources_phase,
    "".join("\t\t\t\t%s /* %s in Resources */,\n" % (b, os.path.basename(p)) for p, b in zip(
        app_resources + app_catalogs,
        app_resource_bfs + [asset_build_ids[c] for c in app_catalogs])),
    ui_resources_phase,
    app_sources_phase,
    "".join("\t\t\t\t%s /* %s in Sources */,\n" % (b, os.path.basename(p)) for p, b in zip(app_sources, app_source_bfs)),
    ui_sources_phase,
    "".join("\t\t\t\t%s /* %s in Sources */,\n" % (b, os.path.basename(p)) for p, b in zip(ui_sources, ui_source_bfs)),
    ui_dependency, app_target, PROJECT, ui_proxy,
    configs["project_debug"], project_settings,
    configs["project_release"], project_settings,
    configs["app_debug"], common_app_settings,
    configs["app_release"], common_app_settings,
    configs["ui_debug"], common_ui_settings,
    configs["ui_release"], common_ui_settings,
    project_config_list, PROJECT, configs["project_debug"], configs["project_release"],
    app_config_list, PROJECT, configs["app_debug"], configs["app_release"],
    ui_config_list, PROJECT, configs["ui_debug"], configs["ui_release"],
    project_object,
)

# ---- Widget extension ---------------------------------------------------------
# The base template renders the app and UI-test targets; the widget target, its
# embed phase, and its build configurations are injected here so the long
# positional template above stays untouched at those definition sites.

widget_source_list = "".join(
    "\t\t\t\t%s /* %s in Sources */,\n" % (widget_bfs[path], os.path.basename(path)) for path in widget_sources)
# Widget source PBXBuildFile entries are rendered by render_build_files_with_assets();
# only the app-extension embed needs injecting here.
widget_embed_build_file = (
    "\t\t%s /* VoltLinkWidgets.appex in Embed App Extensions */ = {isa = PBXBuildFile; fileRef = %s /* VoltLinkWidgets.appex */; "
    "settings = {ATTRIBUTES = (RemoveHeadersOnCopy, CodeSignOnCopy, ); }; };\n" % (widget_embed_bf, widget_product))


def insert_before(marker, block):
    global content
    if marker not in content:
        raise SystemExit("missing pbxproj marker: %s" % marker)
    content = content.replace(marker, block + marker, 1)


insert_before("/* End PBXBuildFile section */", widget_embed_build_file)

insert_before(
    "/* End PBXContainerItemProxy section */",
    "\t\t%s /* PBXContainerItemProxy */ = {\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = %s /* Project Object */;\n"
    "\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = %s;\n\t\t\tremoteInfo = VoltLinkWidgets;\n\t\t};\n"
    % (widget_proxy, project_object, widget_target),
)

insert_before(
    "/* End PBXFrameworksBuildPhase section */",
    "\t\t%s /* Frameworks */ = {\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n" % (widget_frameworks_phase,),
)

insert_before(
    "/* Begin PBXResourcesBuildPhase section */",
    "/* Begin PBXCopyFilesBuildPhase section */\n"
    "\t\t%s /* Embed App Extensions */ = {\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n"
    "\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n\t\t\t\t%s /* VoltLinkWidgets.appex in Embed App Extensions */,\n\t\t\t);\n"
    "\t\t\tname = \"Embed App Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n"
    "/* End PBXCopyFilesBuildPhase section */\n\n" % (widget_embed_phase, widget_embed_bf),
)

insert_before(
    "/* End PBXNativeTarget section */",
    "\t\t%s /* VoltLinkWidgets */ = {\n\t\t\tisa = PBXNativeTarget;\n"
    "\t\t\tbuildConfigurationList = %s /* Build configuration list for PBXNativeTarget \"VoltLinkWidgets\" */;\n\t\t\tbuildPhases = (\n"
    "\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Resources */,\n\t\t\t\t%s /* Frameworks */,\n\t\t\t);\n"
    "\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n\t\t\t);\n\t\t\tname = VoltLinkWidgets;\n\t\t\tproductName = VoltLinkWidgets;\n"
    "\t\t\tproductReference = %s /* VoltLinkWidgets.appex */;\n\t\t\tproductType = \"com.apple.product-type.app-extension\";\n\t\t};\n"
    % (widget_target, widget_config_list, widget_sources_phase, widget_resources_phase, widget_frameworks_phase, widget_product),
)

insert_before(
    "/* End PBXResourcesBuildPhase section */",
    "\t\t%s /* Resources */ = {\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n"
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n" % (widget_resources_phase,),
)

insert_before(
    "/* End PBXSourcesBuildPhase section */",
    "\t\t%s /* Sources */ = {\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n%s\t\t\t);\n"
    "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n" % (widget_sources_phase, widget_source_list),
)

insert_before(
    "/* End PBXTargetDependency section */",
    "\t\t%s /* PBXTargetDependency */ = {\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = %s /* VoltLinkWidgets */;\n"
    "\t\t\ttargetProxy = %s /* PBXContainerItemProxy */;\n\t\t};\n" % (widget_dependency, widget_target, widget_proxy),
)

insert_before(
    "/* End XCBuildConfiguration section */",
    "\t\t%s /* Debug */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\t\t\t};\n\t\t\tname = Debug;\n\t\t};\n"
    "\t\t%s /* Release */ = {\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {\n%s\t\t\t};\n\t\t\tname = Release;\n\t\t};\n"
    % (configs["widget_debug"], common_widget_settings, configs["widget_release"], common_widget_settings),
)

insert_before(
    "/* End XCConfigurationList section */",
    "\t\t%s /* Build configuration list for PBXNativeTarget \"VoltLinkWidgets\" */ = {\n\t\t\tisa = XCConfigurationList;\n"
    "\t\t\tbuildConfigurations = (\n\t\t\t\t%s /* Debug */,\n\t\t\t\t%s /* Release */,\n\t\t\t);\n"
    "\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t};\n"
    % (widget_config_list, configs["widget_debug"], configs["widget_release"]),
)

# App target: embed the extension and depend on it.
app_phases = (
    "\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Resources */,\n\t\t\t\t%s /* Frameworks */,\n\t\t\t);"
    % (app_sources_phase, app_resources_phase, app_frameworks_phase)
)
app_phases_with_embed = (
    "\t\t\tbuildPhases = (\n\t\t\t\t%s /* Sources */,\n\t\t\t\t%s /* Resources */,\n\t\t\t\t%s /* Frameworks */,\n"
    "\t\t\t\t%s /* Embed App Extensions */,\n\t\t\t);"
    % (app_sources_phase, app_resources_phase, app_frameworks_phase, widget_embed_phase)
)
if app_phases not in content:
    raise SystemExit("missing app build phases")
content = content.replace(app_phases, app_phases_with_embed, 1)

content = content.replace(
    "\t\t\tdependencies = (\n\t\t\t);",
    "\t\t\tdependencies = (\n\t\t\t\t%s /* PBXTargetDependency */,\n\t\t\t);" % (widget_dependency,),
    1,
)

targets_marker = (
    "\t\t\ttargets = (\n\t\t\t\t%s /* %s */,\n\t\t\t\t%s /* %sUITests */,\n\t\t\t);" % (app_target, PROJECT, ui_target, PROJECT)
)
if targets_marker not in content:
    raise SystemExit("missing project targets list")
content = content.replace(
    targets_marker,
    "\t\t\ttargets = (\n\t\t\t\t%s /* %s */,\n\t\t\t\t%s /* %sUITests */,\n\t\t\t\t%s /* VoltLinkWidgets */,\n\t\t\t);"
    % (app_target, PROJECT, ui_target, PROJECT, widget_target),
    1,
)

content = content.replace(
    "\t\t\t\tTargetAttributes = {\n",
    "\t\t\t\tTargetAttributes = {\n\t\t\t\t\t%s = {\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n\t\t\t\t\t};\n" % (widget_target,),
    1,
)

pathlib.Path("VoltLink.xcodeproj").mkdir(exist_ok=True)
pathlib.Path("VoltLink.xcodeproj/project.pbxproj").write_text(content, encoding="utf-8")

scheme_dir = pathlib.Path("VoltLink.xcodeproj/xcshareddata/xcschemes")
scheme_dir.mkdir(parents=True, exist_ok=True)
scheme = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "%s.app" BlueprintName = "%s" ReferencedContainer = "container:VoltLink.xcodeproj"/>
         </BuildActionEntry>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "NO" buildForProfiling = "NO" buildForArchiving = "NO" buildForAnalyzing = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "%sUITests.xctest" BlueprintName = "%sUITests" ReferencedContainer = "container:VoltLink.xcodeproj"/>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "%sUITests.xctest" BlueprintName = "%sUITests" ReferencedContainer = "container:VoltLink.xcodeproj"/>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "%s.app" BlueprintName = "%s" ReferencedContainer = "container:VoltLink.xcodeproj"/>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "%s" BuildableName = "%s.app" BlueprintName = "%s" ReferencedContainer = "container:VoltLink.xcodeproj"/>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"/>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"/>
</Scheme>
""" % (app_target, PROJECT, PROJECT, ui_target, PROJECT, PROJECT,
       ui_target, PROJECT, PROJECT,
       app_target, PROJECT, PROJECT,
       app_target, PROJECT, PROJECT)

(scheme_dir / "VoltLink.xcscheme").write_text(scheme, encoding="utf-8")

print("VoltLink.xcodeproj generated (%d app sources, %d resources, %d UI tests)%s" % (
    len(app_sources), len(app_resources) + len(app_catalogs), len(ui_sources),
    " with local signing (no CarPlay or App Group entitlements)" if LOCAL_SIGNING else ""))
