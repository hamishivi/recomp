#!/usr/bin/env python3
"""Source contracts only; these are not a native UI execution or accessibility audit."""
from pathlib import Path
r = Path(__file__).resolve().parents[1]
f = (r/'Recomp/Views/MealEstimatorView.swift').read_text()
i = (r/'Recomp/Views/EstimatedFoodEditor.swift').read_text()
s = (r/'Recomp/Views/SettingsScreen.swift').read_text()
h = (r/'Recomp/Views/RootView.swift').read_text()
d = (r/'Recomp/Views/InstrumentStyle.swift').read_text()
n = 0
def check(value, label):
    global n
    assert value, label
    n += 1; print('PASS:', label)
check('private enum FoodSheet' in f and f.count('.sheet(item: $sheet)') == 1, 'Single modal route for settings, saved foods, ingredients and photos')
check('onChange(of: model.inputRevision)' in f, 'Canonical draft replacement refreshes numeric fields even at equal totals')
check('onEditingEnded: { model.finishManualEditing() }' in f, 'Typing undo groups end with field focus')
check('food.undo' in f and 'ToolbarItem(placement: .topBarTrailing)' in f, 'Undo is a toolbar action independent of item count')
check('PhotoImportSession()' in f and 'photoImport.accepts(ticket)' in f and 'photoImport.finish(ticket)' in f, 'Stale photo batches cannot commit or clear a newer load')
check('model.photos.append(contentsOf: prepared)' in f, 'Photo selection commits a complete prepared batch')
check('private struct MealPhotoTile' in f and '@State private var image: UIImage?' in f, 'Decoded thumbnails retained across unrelated form edits')
check('model.scalePortion(by:' in f and 'inputs.scale(' not in f, 'Portion actions use tested ingredient-preserving operation')
check('model.isExistingMeal && !model.hasChanges' in f, 'No-op save closes without a diary or Health write')
check('model.editorLock(for: food)' in f, 'Unchanged ingredient lock survives opening its editor')
check('interactiveDismissDisabled(hasChanges)' in i and 'confirmDiscard' in i, 'Ingredient sheet guards unsaved changes')
check('original.evidence' in i and 'DisclosureGroup("Sources")' in i, 'Food evidence remains available in ingredient editor')
check('HealthSettingsScreen()' in s and 'private struct HealthSettingsScreen' in s, 'Health connection controls live in a submenu')
check('private func export(_ kind: CSVExportKind)' in s and 'document: exportDocument' in s, 'CSV data prepared on request, not every form render')
check('AnalysisCSV.hasRecords(in: diary.state)' in s, 'History-only analysis exports remain enabled')
check('NavigationLink { SavedFoodsSettings() }' in s, 'Saved foods remains a submenu')
check('IntakeRings' in d and 'ViewThatFits(in: .horizontal)' in d and 'private var stacked' in d, 'Compact rings use a stacked fallback')
check('return "At target"' in d and 'abs(remaining) < 1' in d, 'Small balances do not read as zero over target')
check('accessibilityReduceMotion' in d and 'dynamicType.isAccessibilitySize' in d, 'Reduced motion and large type retained')
check('if !status.isEmpty' in h and 'return "Saved on device"' not in h, 'Successful per-meal status is not repeated on every row')
check('Label("Check food"' in h and 'Label("Log food"' in h, 'Check stays separate from actual logging')
print(f'{n} polish source contracts passed. NOT native rendering or UI behavior tests.')
