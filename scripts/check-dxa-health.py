#!/usr/bin/env python3
"""Static DXA Health routing/privacy checks; NOT a native SDK compile or integration test."""
from pathlib import Path
import plistlib
root = Path(__file__).resolve().parents[1]
app = root / 'Recomp'
service = (app/'Services/HealthKitService.swift').read_text()
store = (app/'Services/DiaryStore.swift').read_text()
views = (app/'Views/DXAHealthViews.swift').read_text()
checks = 0
def check(ok, label):
    global checks
    assert ok, label
    checks += 1
    print('PASS:', label)
part = service[service.index('    func upsertDXA('):service.index('    func removeDXA(')]
for token in ['.bodyMass', '.bodyFatPercentage', '.leanBodyMass']:
    check(token in service[service.index('    static func dxaType('):], 'DXA maps ' + token)
check('metric == .bodyFat ? .percent() : .gramUnit(with: .kilo)' in service, 'DXA Health units explicit')
check('candidate.metric.healthValue(candidate.value)' in part, 'percent conversion used at native boundary')
check('HKMetadataKeySyncIdentifier' in part and 'HKMetadataKeySyncVersion' in part, 'versioned stable DXA identity')
check('start: link.date, end: link.date' in part, 'reviewed timestamp used')
check('HKMetadataKeyTimeZone: link.timeZoneID' in part, 'selected timezone retained')
check('link.date <= Date()' in part, 'future export timestamp blocked')
check('retainedPDF' not in part and 'sourceExcerpt' not in part and 'scan.provider' not in part, 'no PDF/excerpt/provider field upload')
check('DXAHealthIdentity.methodMetadataKey: "DXA"' in part, 'DXA provenance marker')
access = service[service.index('    func requestDXAAccess('):service.index('    func upsertDXA(')]
check('read: []' in access, 'scan sharing does not request unrelated Health reads')
remove = service[service.index('    func removeDXA('):service.index('    private func query(')]
check('HKSource.default()' in remove and 'NSCompoundPredicate(andPredicateWithSubpredicates: [identifier, source])' in remove, 'deletions restricted to own exact identity and source')
check('isRecompDXA: isDXASample(sample)' in service, 'ordinary body read carries DXA exclusion')
check('guard !isDXASample(sample)' in service, 'legacy weight read excludes own DXA')
check('healthBodySamples = body.samples.filter { !$0.isRecompDXA }' in store, 'DXA samples removed before scale UI and analysis')
check('state.dxaScans.first(where: { $0.id == reviewedScan.id }) == reviewedScan' in store, 'stale sharing snapshot rejected')
check('attemptedMetrics.insert(metric)' in store, 'attempt receipt persisted before call')
check('selectedMetrics = []' in store[store.index('    func removeDXAScan'):store.index('    var pendingDXAMetrics')], 'scan deletion deselects all metrics for cleanup')
check('I reviewed the selected values and time' in views, 'explicit export review gate')
check('Pause DEXA syncing' in views and 'Remove this scan\'s Health exports' in views, 'pause versus removal controls present')
check('Time is approximate' in views and 'Scan timezone' in views, 'timestamp caveats and timezone control')
plist=plistlib.loads((app/'Info.plist').read_bytes())
check('DEXA' in plist['NSHealthUpdateUsageDescription'] and 'lean body mass' in plist['NSHealthUpdateUsageDescription'], 'Health purpose string includes new fields')
check('Recomp/Core/DXAHealth.swift' in (root/'Recomp.xcodeproj/project.pbxproj').read_text(), 'new core file is in native build')
check('Recomp/Views/DXAHealthViews.swift' in (root/'Recomp.xcodeproj/project.pbxproj').read_text(), 'new view file is in native build')
print(f'{checks} static DXA Health checks passed. Not native integration tests.')
