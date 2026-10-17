#!/usr/bin/env python3
"""Static wiring/privacy checks only: these DO NOT build or render an iPhone app."""
from pathlib import Path
import re, plistlib, json
R=Path(__file__).resolve().parents[1]
n=0
def check(ok, label):
 global n
 assert ok,label
 n+=1;print('PASS:',label)
def read(p):return (R/p).read_text()
project=read('Recomp.xcodeproj/project.pbxproj')
defs=re.findall(r'^\s*([A-F0-9]{24}) = \{',project,re.M)
check(len(defs)==len(set(defs)), 'Project object identifiers unique')
refs=set(re.findall(r'\b[A-F0-9]{24}\b',project))
check(refs<=set(defs), 'All project object references resolve')
for p in list((R/'Recomp').rglob('*.swift'))+list((R/'RecompWidget').glob('*.swift')):
 check(str(p.relative_to(R)) in project, f'Project includes {p.name}')
check('com.apple.product-type.app-extension' in project, 'Native WidgetKit extension target')
check('PBXTargetDependency' in project and 'PBXContainerItemProxy' in project, 'App builds widget dependency')
check('dstSubfolderSpec = 13' in project and 'Embed App Extensions' in project, 'Widget embedded in app Plugins directory')
check('APPLICATION_EXTENSION_API_ONLY = "YES"' in project, 'Widget extension API-only build setting')
for folder,file in [('Recomp','Recomp.entitlements'),('RecompWidget','RecompWidget.entitlements')]:
 e=plistlib.loads((R/folder/file).read_bytes())
 check(e['com.apple.security.application-groups']==['$(RECOMP_APP_GROUP)'], f'{folder} shares configured App Group')
 info=plistlib.loads((R/folder/'Info.plist').read_bytes())
 check(info['RecompAppGroup']=='$(RECOMP_APP_GROUP)', f'{folder} group read uses build setting')
widgetEnt=plistlib.loads((R/'RecompWidget/RecompWidget.entitlements').read_bytes())
check(widgetEnt['com.apple.developer.default-data-protection']=='NSFileProtectionComplete', 'Widget complete Data Protection entitlement')
w=read('RecompWidget/RecompWidget.swift')
check('import HealthKit' not in w and 'URLSession' not in w, 'Widget reads no Health records or network')
check('.privacySensitive()' in w and 'snapshot.isCurrent' in w, 'Sensitive fields and stale-day guard')
check('snapshot: nil' in w and 'midnight' in w, 'Midnight entry hides prior-day data')
for route in ['log','check','weigh']:
 check('recomp://'+route in w, f'Native widget shortcut {route}')
pub=read('Recomp/Services/WidgetPublisher.swift')
check('.completeFileProtection' in pub and 'isExcludedFromBackup' in pub, 'Protected and backup-excluded shared snapshot')
act=read('Recomp/Services/ActivityHealthService.swift')
check('toShare: []' in act, 'Activity permission is read-only')
check('store.save' not in act and 'store.delete' not in act, 'Activity cannot write/delete workouts')
check('HKStatisticsCollectionQuery' in act and '.cumulativeSum' in act, 'Steps use merged statistics')
check('asleepCore' in act and 'asleepREM' in act and 'asleepDeep' in act, 'Asleep stages explicitly selected')
check('URLSession' not in act and 'route' not in act.lower().split('final class')[1], 'No activity network/route fetch')
check('totalEnergyBurned' not in act, 'Workout calories are not imported as an eat-back allowance')
ui=read('Recomp/Views/MealEstimatorView.swift')
check('if mode == .log' in ui and 'guard mode == .log' in ui, 'Check mode cannot invoke save')
check('Log this food' in ui and 'mode = .log' in ui, 'Separate explicit handoff to logging')
check('maxSelectionCount:' in ui and 'private struct MealPhotoDetails' in ui and 'Picker("Shows", selection: $photo.role)' in ui, 'Native multi-select and editable photo roles')
check('Keep photos attached' in ui, 'Visible local photo-retention choice')
server=read('Server/estimate.mjs')
check("raw.images.length <= 6" in server and 'photoEvidence' in server, 'Six images and evidence context accepted')
check("nutritionLabel" in server and 'leftovers' in server, 'Labels/leftovers handled as photo evidence')
check('12_300_000' in read('Server/server.mjs'), 'Server request bound increased for six images')
crypto=read('Recomp/Services/BackupCrypto.swift')
check('AES.GCM.seal' in crypto and 'AES.GCM.open' in crypto, 'Uses platform authenticated encryption')
check('kCCPRFHmacAlgSHA256' in crypto and 'CCKeyDerivationPBKDF' in crypto, 'Uses platform PBKDF2-HMAC-SHA256')
check('SecRandomCopyBytes' in crypto, 'Native random salt')
check('authenticating: envelope.authenticatedData' in crypto, 'Backup header authenticated')
check('URLSession' not in crypto and 'UserDefaults' not in crypto, 'Crypto contains no upload or password persistence')
restore=read('Recomp/Core/BackupPayload.swift')
check('current.canRestoreBackup' in restore and 'self.bundleID == bundleID' in restore, 'Empty-only matching-identity restore gate')
for name in ['healthEnabled','bodyHealthEnabled','dxaHealthEnabled','activityPreferences.enabled','widgetPreferences.showNumbers']:
 check('result.'+name+' = false' in restore, f'Restore disables {name}')
check('EstimatorKeychain' not in restore and 'accessToken' not in restore, 'Backup payload does not include estimator credentials')
print(f'{n} static feature wiring checks passed. Not native SDK, crypto execution or UI tests.')
