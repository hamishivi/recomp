#!/usr/bin/env python3
"""Static design checks only. Does not compile SwiftUI or validate native accessibility."""
from pathlib import Path
import json
import plistlib
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / 'Recomp'
count = 0

def check(test, label):
    global count
    assert test, label
    count += 1
    print('PASS:', label)

def luminance(rgb):
    def convert(v): return v/12.92 if v <= .04045 else ((v+.055)/1.055)**2.4
    return sum(convert(v)*w for v,w in zip(rgb,[.2126,.7152,.0722]))

def contrast(a,b):
    a,b=sorted((luminance(a),luminance(b)))
    return (b+.05)/(a+.05)

assets = {}
for p in (APP/'Assets.xcassets').rglob('*.colorset/Contents.json'):
    data=json.loads(p.read_text()); values={}
    for color in data['colors']:
        modes={v['appearance']:v['value'] for v in color.get('appearances',[])}
        key=(modes.get('luminosity','light'),modes.get('contrast','standard'))
        c=color['color']['components']
        values[key]=[float(c[k]) for k in ('red','green','blue')]
    assets[p.parent.stem]=values

for mode in [('light','standard'),('dark','standard'),('light','high'),('dark','high')]:
    for fg in ['Ink','Muted','AccentColor']:
        for bg in ['Canvas','Panel']:
            ratio=contrast(assets[fg][mode],assets[bg][mode])
            check(ratio>=4.5, f'{mode}: {fg} on {bg} {ratio:.2f}:1')
    check(contrast([.08,.09,.07],assets['Signal'][mode])>=4.5, f'{mode}: primary button text contrast')

style=(APP/'Views/InstrumentStyle.swift').read_text()
check('@ScaledMetric' in style and 'dynamicType.isAccessibilitySize' in style, 'Scalable readout and accessibility layout present')
check('ViewThatFits' in style, 'Adaptive text rows present')
check('.accessibilityHidden(true)' in style, 'Decorative ruler hidden from accessibility')
check('buttonStyle(.borderedProminent)' in style and 'DragGesture' not in style and 'struct InstrumentButtonStyle' not in style, 'Native bordered-prominent button styling; no drag gesture replacement')
app=(APP/'RecompApp.swift').read_text()
check('preferredColorScheme(.dark)' not in app and 'AppAppearance.storageKey' in app, 'No forced dark mode in app')
views='\n'.join(p.read_text() for p in (APP/'Views').glob('*.swift'))
check('Theme.mint' not in views and 'design: .rounded' not in views, 'No old neon/rounded-number styling')
check('MacroCard' not in views, 'Single macro readout replaces colored cards')
check('TabView(selection:' in views and 'NavigationStack' in views and 'PhotosPicker' in views, 'Native navigation and photo picker retained')
check('instrumentChart()' in (APP/'Views/ScaleLocationViews.swift').read_text(), 'Scale charts share the theme')
check('.symbol(by:' in (APP/'Views/ScaleLocationViews.swift').read_text(), 'Chart series use symbols as well as color')
preview=(APP/'Views/InterfacePreviewScreen.swift').read_text()
check(not re.search(r'\bDiaryStore\s*\(|@EnvironmentObject|saveEntry\(|setTargets\(|connectHealth\(',preview), 'Read-only gallery has no diary or Health connection')
plist=plistlib.loads((APP/'PrivacyInfo.xcprivacy').read_bytes())
check(any(x['NSPrivacyAccessedAPIType']=='NSPrivacyAccessedAPICategoryUserDefaults' and 'CA92.1' in x['NSPrivacyAccessedAPITypeReasons'] for x in plist['NSPrivacyAccessedAPITypes']), 'Appearance preference has UserDefaults privacy reason')
for p in APP.rglob('*.plist'): plistlib.loads(p.read_bytes())
plistlib.loads((APP/'Recomp.entitlements').read_bytes())
ET.parse(ROOT/'Recomp.xcodeproj/xcshareddata/xcschemes/Recomp.xcscheme')
check(True, 'Property lists and shared scheme parse')
project=(ROOT/'Recomp.xcodeproj/project.pbxproj').read_text()
for p in APP.rglob('*.swift'):
    check(p.relative_to(ROOT).as_posix() in project, f'Project includes {p.name}')
print(f'\n{count} static interface checks passed. Token contrasts only, not a native UI/accessibility audit.')
