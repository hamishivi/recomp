#!/usr/bin/env python3
"""UI source contracts only, NOT a simulator test."""
from pathlib import Path
import re, json, runpy, contextlib, io
r=Path(__file__).resolve().parents[1]
def read(p): return (r/p).read_text()
n=0
def check(v,msg):
 global n
 assert v,msg
 n+=1; print('PASS:',msg)
home=read('Recomp/Views/RootView.swift'); style=read('Recomp/Views/InstrumentStyle.swift')
form=read('Recomp/Views/MealEstimatorView.swift');model=read('Recomp/Services/MealEstimatorModel.swift')
settings=read('Recomp/Views/SettingsScreen.swift')
check('.navigationTitle("Recomp")' not in home,'Home has no Recomp title')
check('showEstimator' not in home and 'Label("Estimate"' not in home,'No separate home estimate path')
check('NutritionSummary(' in home and 'EnergyReadout' not in home and 'MacroReadout' not in home,'One nutrition summary')
check('quickAdd' not in home and 'Your usuals' not in home,'Usuals removed from home')
check('FoodEditor(entry:' in home and 'case .log: FoodEditor' in home,'Home/widget open same food flow')
check('MealEstimatorView(' in read('Recomp/Views/FoodEditor.swift'),'Manual editor delegates to unified composer')
check('NutritionFields(inputs: nutritionBinding' in form and 'photoSection' in form,'Typed totals and photos in same form')
check('if mode == .log' in form and 'guard mode == .log' in form,'Check cannot save without explicit mode switch')
check('Log this food' in form and 'mode = .log' in form,'Check handoff remains explicit')
check('saved ||' not in form or 'guard mode' in form,'Save path guarded')
check('confirmUpload = true' in form and '.confirmationDialog("Send to AI?"' in form,'Explicit upload approval retained')
check('interactiveDismissDisabled' in form and 'Discard changes?' in form,'Unsaved edits cannot silently swipe away')
check('SavedFoodPicker' in form and 'Replace the current food?' in form,'Usual replacement reviewed')
check('onSelect(food); dismiss()' in form,'Usual chooser populates draft only')
check('NavigationLink { SavedFoodsSettings() }' in settings,'Settings usuals is a submenu')
check('swipeActions' in settings,'Remove usual retained in submenu')
check('Text(number)' not in style and not re.search(r'SectionHeading\(number:', '\n'.join(p.read_text() for p in (r/'Recomp/Views').glob('*.swift'))),'No numbered section badges remain')
check('strokeBorder(Theme.rule, lineWidth: 1)' in style,'Panels have visible borders')
check('Nutrient.allCases.enumerated()' in style and 'Circle().trim' in style,'Four native vector rings')
check('accessibilityReduceMotion' in style and 'reduceMotion ? nil' in style,'Ring animation respects Reduce Motion')
check('progress.remaining' in style and 'No target' in style,'Exact balances and zero-target state stay visible')
check('dynamicType.isAccessibilitySize' in style and '.accessibilityLabel(' in style,'Large-text fallback and labelled values')
check('struct IntakeRingProgress' in read('Recomp/Core/DiaryMath.swift'),'Testable ring math')
# Contrast: decorative ring arc relative to its 15% tint track in each appearance.
with contextlib.redirect_stdout(io.StringIO()): tokens=runpy.run_path(str(r/'scripts/check-interface.py'))
assets=tokens['assets']; contrast=tokens['contrast']
for mode in [('light','standard'),('dark','standard'),('light','high'),('dark','high')]:
 for name in ['RingCalories','RingProtein','RingCarbs','RingFat']:
  color=assets[name][mode]; panel=assets['Panel'][mode]; track=[.15*c+.85*b for c,b in zip(color,panel)]
  check(contrast(color,track)>=3,f'{name} {mode}: arc/track contrast >=3')
print(f'{n} UI source/contrast checks passed. No native rendering or UI execution.')
