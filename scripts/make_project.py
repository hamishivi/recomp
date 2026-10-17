#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project. No XcodeGen or CocoaPods required."""
import argparse
import hashlib
import json
import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--bundle-id', default='com.example.recomp')
parser.add_argument('--app-group', default='group.com.example.recomp')
parser.add_argument('--team', default='')
args = parser.parse_args()
for value in (args.bundle_id, args.app_group, args.team):
    if value and not all(c.isalnum() or c in '.-' for c in value): parser.error('Identifiers may contain only letters, numbers, dots and hyphens.')
if not args.app_group.startswith('group.'): parser.error('The App Group must begin with group.')

def ident(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def q(s): return json.dumps(str(s))
objects = []
def obj(name, contents):
    i = ident(name)
    objects.append(f"\t\t{i} = {{ {contents} }};")
    return i

def array(ids): return "(" + ", ".join(ids) + (", " if ids else "") + ")"

sources = sorted((ROOT / 'Recomp').rglob('*.swift'))
source_refs, source_builds = [], []
for f in sources:
    path = f.relative_to(ROOT).as_posix()
    ref = obj('file:'+path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = "<group>";')
    source_refs.append(ref)
    source_builds.append(obj('build:'+path, f'isa = PBXBuildFile; fileRef = {ref};'))
resource_refs, resource_builds = [], []
for path, kind in [('Recomp/Assets.xcassets', 'folder.assetcatalog'), ('Recomp/PrivacyInfo.xcprivacy', 'text.xml')]:
    ref = obj('file:'+path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(path)}; sourceTree = "<group>";')
    resource_refs.append(ref)
    resource_builds.append(obj('build:'+path, f'isa = PBXBuildFile; fileRef = {ref};'))
for path in ['Recomp/Info.plist', 'Recomp/Recomp.entitlements']:
    resource_refs.append(obj('file:'+path, f'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {q(path)}; sourceTree = "<group>";'))
health_ref = obj('HealthKit.framework', 'isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = HealthKit.framework; path = System/Library/Frameworks/HealthKit.framework; sourceTree = SDKROOT;')
health_build = obj('HealthKit.build', f'isa = PBXBuildFile; fileRef = {health_ref};')
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Recomp.app; sourceTree = BUILT_PRODUCTS_DIR;')
widget_source = obj('file:RecompWidget/RecompWidget.swift', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = RecompWidget/RecompWidget.swift; sourceTree = "<group>";')
widget_builds = [obj('widgetBuild', f'isa = PBXBuildFile; fileRef = {widget_source};'),
    obj('widgetSharedBuild', f'isa = PBXBuildFile; fileRef = {ident("file:Recomp/Core/WidgetSnapshot.swift")};')]
widget_refs = [widget_source]
widget_resources = []
for path, kind in [('RecompWidget/Assets.xcassets','folder.assetcatalog'), ('RecompWidget/PrivacyInfo.xcprivacy','text.xml')]:
    ref = obj('file:'+path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {q(path)}; sourceTree = "<group>";')
    widget_refs.append(ref); widget_resources.append(obj('widget:'+path, f'isa = PBXBuildFile; fileRef = {ref};'))
for path in ['RecompWidget/Info.plist', 'RecompWidget/RecompWidget.entitlements']:
    widget_refs.append(obj('file:'+path, f'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = {q(path)}; sourceTree = "<group>";'))
widget_product = obj('widgetProduct', 'isa = PBXFileReference; explicitFileType = "wrapper.app-extension"; includeInIndex = 0; path = RecompWidget.appex; sourceTree = BUILT_PRODUCTS_DIR;')
widget_group = obj('widgetGroup', f'isa = PBXGroup; children = {array(widget_refs)}; name = Widget; sourceTree = "<group>";')
widget_sources_phase = obj('widgetSourcesPhase', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(widget_builds)}; runOnlyForDeploymentPostprocessing = 0;')
widget_resources_phase = obj('widgetResourcesPhase', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(widget_resources)}; runOnlyForDeploymentPostprocessing = 0;')
widget_frameworks_phase = obj('widgetFrameworkPhase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
embed_build = obj('widgetEmbedBuild', f'isa = PBXBuildFile; fileRef = {widget_product}; platformFilters = (ios, ); settings = {{ ATTRIBUTES = (RemoveHeadersOnCopy, ); }};')
embed_phase = obj('widgetEmbedPhase', f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 13; files = {array([embed_build])}; name = "Embed App Extensions"; runOnlyForDeploymentPostprocessing = 0;')
widget_proxy = obj('widgetProxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("widgetTarget")}; remoteInfo = RecompWidget;')
widget_dependency = obj('widgetDependency', f'isa = PBXTargetDependency; platformFilters = (ios, ); target = {ident("widgetTarget")}; targetProxy = {widget_proxy};')
# Executable Apple-SDK tests. These are not app resources or production fixtures.
# Hostless core/crypto tests never launch the app or request Health permissions.
def add_test_target(name, paths, ui=False, fixture=None):
    refs, builds, resource_builds = [], [], []
    for f in paths:
        path = f.relative_to(ROOT).as_posix()
        # A PBXFileReference can appear in only one PBXGroup.  Tests compile
        # selected production sources directly, so they need their own file
        # references instead of reusing the Sources-group references.
        ref = obj(name+':file:'+path, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(path)}; sourceTree = "<group>";')
        refs.append(ref)
        builds.append(obj(name+':build:'+path, f'isa = PBXBuildFile; fileRef = {ref};'))
    if fixture:
        ref = obj(name+':fixture', f'isa = PBXFileReference; lastKnownFileType = file; path = {q(fixture)}; sourceTree = "<group>";')
        refs.append(ref)
        resource_builds.append(obj(name+':fixtureBuild', f'isa = PBXBuildFile; fileRef = {ref};'))
    group = obj(name+':group', f'isa = PBXGroup; children = {array(refs)}; name = {name}; sourceTree = "<group>";')
    product = obj(name+':product', f'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = {name}.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
    phases = [obj(name+':sourcePhase', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(builds)}; runOnlyForDeploymentPostprocessing = 0;'),
        obj(name+':resourcePhase', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;'),
        obj(name+':frameworkPhase', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')]
    configs = []
    for config in ['Debug','Release']:
        values = {'CODE_SIGN_STYLE':'Automatic','DEVELOPMENT_TEAM':args.team,
            'PRODUCT_BUNDLE_IDENTIFIER':args.bundle_id+'.'+name, 'PRODUCT_NAME':'$(TARGET_NAME)',
            'GENERATE_INFOPLIST_FILE':'YES', 'TARGETED_DEVICE_FAMILY':'1',
            'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST':'NO',
            'ENABLE_TESTING_SEARCH_PATHS':'YES', 'SKIP_INSTALL':'YES',
            'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @loader_path/Frameworks @executable_path/Frameworks',
            'SWIFT_ACTIVE_COMPILATION_CONDITIONS':'$(inherited) RECOMP_NATIVE_TESTS'}
        if ui: values['TEST_TARGET_NAME'] = 'Recomp'
        encoded = ' '.join(f'{k} = {q(v)};' for k,v in values.items())
        configs.append(obj(name+':config:'+config, f'isa = XCBuildConfiguration; buildSettings = {{ {encoded} }}; name = {config};'))
    config_list = obj(name+':configList', f'isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug;')
    dependencies = []
    if ui:
        proxy = obj(name+':proxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("target")}; remoteInfo = Recomp;')
        dependencies.append(obj(name+':dependency', f'isa = PBXTargetDependency; target = {ident("target")}; targetProxy = {proxy};'))
    kind = 'ui-testing' if ui else 'unit-test'
    target = obj(name+':target', f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = {array(phases)}; buildRules = (); dependencies = {array(dependencies)}; name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.bundle.{kind}";')
    return group, product, target, name
native_tests = add_test_target('RecompNativeTests',
    sorted((ROOT/'Recomp/Core').glob('*.swift')) + sorted((ROOT/'Tests/RecompCoreTests').glob('*.swift')) +
    [ROOT/'Recomp/Services/BackupCrypto.swift'] + sorted((ROOT/'TestSupport/NativeTests').glob('*.swift')),
    fixture='TestSupport/Fixtures/backup-reference.recompbackup')
ui_tests = add_test_target('RecompUITests', sorted((ROOT/'RecompUITests').glob('*.swift')), ui=True)
test_targets = [native_tests, ui_tests]
src_group = obj('sources', f'isa = PBXGroup; children = {array(source_refs)}; name = Sources; sourceTree = "<group>";')
res_group = obj('resources', f'isa = PBXGroup; children = {array(resource_refs)}; name = Resources; sourceTree = "<group>";')
framework_group = obj('frameworks', f'isa = PBXGroup; children = {array([health_ref])}; name = Frameworks; sourceTree = "<group>";')
product_group = obj('products', f'isa = PBXGroup; children = {array([product, widget_product] + [t[1] for t in test_targets])}; name = Products; sourceTree = "<group>";')
main_group = obj('mainGroup', f'isa = PBXGroup; children = {array([src_group,res_group,widget_group,framework_group,product_group] + [t[0] for t in test_targets])}; sourceTree = "<group>";')
sources_phase = obj('sourcePhase', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(source_builds)}; runOnlyForDeploymentPostprocessing = 0;')
resources_phase = obj('resourcePhase', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;')
frameworks_phase = obj('frameworkPhase', f'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = {array([health_build])}; runOnlyForDeploymentPostprocessing = 0;')

def settings(d): return ' '.join(f'{(q(k) if "[" in k else k)} = {q(v)};' for k,v in d.items())
project_configs, target_configs, widget_configs = [], [], []
for config in ['Debug','Release']:
    common = {
        'ALWAYS_SEARCH_USER_PATHS':'NO','CLANG_ENABLE_MODULES':'YES','CLANG_ENABLE_OBJC_ARC':'YES',
        'CLANG_WARN_DOCUMENTATION_COMMENTS':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17',
        'IPHONEOS_DEPLOYMENT_TARGET':'17.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0',
        'SWIFT_STRICT_CONCURRENCY':'minimal','DEBUG_INFORMATION_FORMAT':'dwarf' if config=='Debug' else 'dwarf-with-dsym',
        'ENABLE_TESTABILITY':'YES' if config=='Debug' else 'NO',
        'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if config=='Debug' else '-O',
        'GCC_OPTIMIZATION_LEVEL':'0' if config=='Debug' else 's',
        'ONLY_ACTIVE_ARCH':'YES' if config=='Debug' else 'NO',
    }
    if config=='Debug':
        common['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG'
        # Keep symbols in Debug copies, including signed preview dylibs.
        common['COPY_PHASE_STRIP'] = 'NO'
    project_configs.append(obj('projectConfig:'+config, f'isa = XCBuildConfiguration; buildSettings = {{ {settings(common)} }}; name = {config};'))
    app = {
        'ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME':'AccentColor',
        'CODE_SIGN_STYLE':'Automatic','CODE_SIGN_ENTITLEMENTS':'Recomp/Recomp.entitlements',
        'CODE_SIGN_ENTITLEMENTS[sdk=macosx*]':'',
        'CODE_SIGN_IDENTITY[sdk=macosx*]':'-',
        'CODE_SIGN_STYLE[sdk=macosx*]':'Manual',
        'PROVISIONING_PROFILE_SPECIFIER[sdk=macosx*]':'',
        'CODE_SIGNING_REQUIRED[sdk=macosx*]':'NO',
        'DEVELOPMENT_TEAM':args.team,'CURRENT_PROJECT_VERSION':'15','MARKETING_VERSION':'1.10.1',
        'RECOMP_APP_GROUP':args.app_group,
        'GENERATE_INFOPLIST_FILE':'NO','INFOPLIST_FILE':'Recomp/Info.plist',
        'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks',
        'PRODUCT_BUNDLE_IDENTIFIER':args.bundle_id,'PRODUCT_NAME':'$(TARGET_NAME)',
        'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator macosx','SUPPORTS_MACCATALYST':'YES',
        'TARGETED_DEVICE_FAMILY':'1,2','ENABLE_PREVIEWS':'YES','SWIFT_EMIT_LOC_STRINGS':'YES',
        'DERIVE_MACCATALYST_PRODUCT_BUNDLE_IDENTIFIER':'NO',
    }
    target_configs.append(obj('targetConfig:'+config, f'isa = XCBuildConfiguration; buildSettings = {{ {settings(app)} }}; name = {config};'))
    widget = dict(app)
    widget.update({'PRODUCT_BUNDLE_IDENTIFIER':args.bundle_id+'.widget', 'CODE_SIGN_ENTITLEMENTS':'RecompWidget/RecompWidget.entitlements',
        'INFOPLIST_FILE':'RecompWidget/Info.plist', 'APPLICATION_EXTENSION_API_ONLY':'YES', 'SKIP_INSTALL':'YES',
        'SUPPORTED_PLATFORMS':'iphoneos iphonesimulator', 'SUPPORTS_MACCATALYST':'NO', 'TARGETED_DEVICE_FAMILY':'1',
        'LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks @executable_path/../../Frameworks'})
    widget.pop('ASSETCATALOG_COMPILER_APPICON_NAME', None)
    widget.pop('ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME', None)
    widget_configs.append(obj('widgetConfig:'+config, f'isa = XCBuildConfiguration; buildSettings = {{ {settings(widget)} }}; name = {config};'))
widget_config_list = obj('widgetConfigList', f'isa = XCConfigurationList; buildConfigurations = {array(widget_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
widget_target = obj('widgetTarget', f'isa = PBXNativeTarget; buildConfigurationList = {widget_config_list}; buildPhases = {array([widget_sources_phase,widget_frameworks_phase,widget_resources_phase])}; buildRules = (); dependencies = (); name = RecompWidget; productName = RecompWidget; productReference = {widget_product}; productType = "com.apple.product-type.app-extension";')
project_config_list = obj('projectConfigList', f'isa = XCConfigurationList; buildConfigurations = {array(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target_config_list = obj('targetConfigList', f'isa = XCConfigurationList; buildConfigurations = {array(target_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {target_config_list}; buildPhases = {array([sources_phase,frameworks_phase,resources_phase,embed_phase])}; buildRules = (); dependencies = {array([widget_dependency])}; name = Recomp; productName = Recomp; productReference = {product}; productType = "com.apple.product-type.application";')
project = obj('project', f'''isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ CreatedOnToolsVersion = 16.0; SystemCapabilities = {{ com.apple.HealthKit = {{ enabled = 1; }}; com.apple.ApplicationGroups.iOS = {{ enabled = 1; }}; }}; }}; }}; }}; buildConfigurationList = {project_config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main_group}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {array([target, widget_target] + [t[2] for t in test_targets])};''')
project_dir = ROOT / 'Recomp.xcodeproj'
project_dir.mkdir(exist_ok=True)
(project_dir / 'project.pbxproj').write_text('// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {};\n\tobjectVersion = 56;\n\tobjects = {\n'+'\n'.join(objects)+f'\n\t}};\n\trootObject = {project};\n}}\n')

ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Recomp.app" BlueprintName="Recomp" ReferencedContainer="container:Recomp.xcodeproj" />'
test_refs = [f'<TestableReference skipped="NO"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{t[2]}" BuildableName="{t[3]}.xctest" BlueprintName="{t[3]}" ReferencedContainer="container:Recomp.xcodeproj" /></TestableReference>' for t in test_targets]
test_build_refs = ''.join(f'<BuildActionEntry buildForTesting="YES" buildForRunning="NO" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{t[2]}" BuildableName="{t[3]}.xctest" BlueprintName="{t[3]}" ReferencedContainer="container:Recomp.xcodeproj" /></BuildActionEntry>' for t in test_targets)
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry>
    {test_build_refs}
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>{"".join(test_refs)}</Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug" />
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES" />
</Scheme>
'''
scheme_dir = project_dir / 'xcshareddata' / 'xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
(scheme_dir / 'Recomp.xcscheme').write_text(scheme)

info = {
    'CFBundleDevelopmentRegion': '$(DEVELOPMENT_LANGUAGE)', 'CFBundleDisplayName': 'Recomp',
    'CFBundleExecutable': '$(EXECUTABLE_NAME)', 'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)',
    'CFBundleInfoDictionaryVersion': '6.0', 'CFBundleName': '$(PRODUCT_NAME)', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '$(MARKETING_VERSION)', 'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)',
    'RecompAppGroup':'$(RECOMP_APP_GROUP)',
    'CFBundleURLTypes':[{'CFBundleURLName':'Recomp', 'CFBundleURLSchemes':['recomp']}],
    'CFBundleDocumentTypes':[{'CFBundleTypeName':'Recomp encrypted backup','CFBundleTypeRole':'Viewer','LSItemContentTypes':['app.recomp.encrypted-backup']}],
    'UTExportedTypeDeclarations':[{'UTTypeIdentifier':'app.recomp.encrypted-backup','UTTypeDescription':'Recomp encrypted backup', 'UTTypeConformsTo':['public.data'], 'UTTypeTagSpecification':{'public.filename-extension':['recompbackup']}}],
    # Supports in-place document access and iCloud sync across iOS and macOS
    'LSSupportsOpeningDocumentsInPlace': True,
    'LSRequiresIPhoneOS': True, 'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False},
    'UIRequiresFullScreen': True,
    'UILaunchScreen': {}, 'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
    'NSCameraUsageDescription': 'Recomp uses your camera to photograph food for estimates that you review before logging. Photos are sent for analysis only after you confirm.',
    'NSAppTransportSecurity': {'NSAllowsLocalNetworking': True},
    'NSLocalNetworkUsageDescription': 'Recomp uses the local network to discover and sync diary entries directly with your Mac or iPhone.',
    'NSBonjourServices': ['_recomp-sync3._tcp'],
    'NSHealthShareUsageDescription': 'Recomp reads nutrition, weight, body-fat percentage and waist for local tracking, plus optional workout summaries, steps and sleep for activity context. No Health records are sent to the food AI service.',
    'NSHealthUpdateUsageDescription': 'Recomp saves the calories and macros you confirm, and optionally weight, body-fat percentage and waist readings. Separately reviewed DEXA scans can share total-body weight, body-fat percentage and compatible lean body mass. It updates or removes only its own samples when you edit or delete records.',
}
for filename, content in [('Info.plist', info), ('Recomp.entitlements', {'com.apple.developer.healthkit': True, 'com.apple.security.application-groups':['$(RECOMP_APP_GROUP)']}),
                          ('PrivacyInfo.xcprivacy', {'NSPrivacyTracking': False, 'NSPrivacyCollectedDataTypes': [
                              {'NSPrivacyCollectedDataType': kind, 'NSPrivacyCollectedDataTypeLinked': True,
                               'NSPrivacyCollectedDataTypeTracking': False,
                               'NSPrivacyCollectedDataTypePurposes': ['NSPrivacyCollectedDataTypePurposeAppFunctionality']}
                              for kind in ['NSPrivacyCollectedDataTypePhotosorVideos', 'NSPrivacyCollectedDataTypeOtherUserContent', 'NSPrivacyCollectedDataTypeHealth']],
                              'NSPrivacyAccessedAPITypes': [{'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults', 'NSPrivacyAccessedAPITypeReasons': ['CA92.1']}, {'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryFileTimestamp','NSPrivacyAccessedAPITypeReasons':['C617.1','3B52.1']}]})]:
    with (ROOT / 'Recomp' / filename).open('wb') as f: plistlib.dump(content, f)
print(f'Wrote project with {len(sources)} Swift sources.')

widget_info = {key: info[key] for key in ['CFBundleDevelopmentRegion','CFBundleExecutable','CFBundleIdentifier',
    'CFBundleInfoDictionaryVersion','CFBundleName','CFBundleShortVersionString','CFBundleVersion','RecompAppGroup']}
widget_info.update({'CFBundlePackageType':'XPC!', 'CFBundleDisplayName':'Recomp Widget',
    'NSExtension':{'NSExtensionPointIdentifier':'com.apple.widgetkit-extension'}})
for filename, content in [('Info.plist', widget_info), ('RecompWidget.entitlements', {
    'com.apple.security.application-groups':['$(RECOMP_APP_GROUP)'],
    'com.apple.developer.default-data-protection':'NSFileProtectionComplete'}),
    ('PrivacyInfo.xcprivacy', {'NSPrivacyTracking':False, 'NSPrivacyCollectedDataTypes':[], 'NSPrivacyAccessedAPITypes':[{'NSPrivacyAccessedAPIType':'NSPrivacyAccessedAPICategoryFileTimestamp','NSPrivacyAccessedAPITypeReasons':['C617.1']}]})]:
    with (ROOT/'RecompWidget'/filename).open('wb') as f: plistlib.dump(content,f)
print('Added embedded WidgetKit extension, App Group setting and native backup document type.')
