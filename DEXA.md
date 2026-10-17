# Recomp 1.6 — DEXA / DXA report ingestion

**Unsigned native iPhone source project. The Xcode build, Apple PDFKit extraction, simulator interface and real-device workflows remain unverified.** See `Verification/BUILD_STATUS.md` for tests actually run.

## Use it

Open **Body → DEXA scans → Add scan**. It is also accessible from **Settings → Measurements & maintenance → DEXA reports & exports**. The existing off-white/graphite/orange design, native forms, navigation, document picker and Charts are retained. No server, API key or additional Health permission is needed.

1. Select **Import report PDF** using the native Files picker. You can instead expand **Paste or inspect report text**, paste selected report text, or skip import and add results manually.
2. Open **View imported PDF** to inspect the original. Under the text disclosure, use **Find labelled values**. Each candidate is unselected: tap it, verify its metric, value, units and anatomical site, then tap **Use value**. No candidate is accepted automatically.
3. Choose the **scan date**, and enter the provider/clinic. The importer does not guess dates from filenames, birthdays, report-generation dates or ambiguous US/Australian date strings. Enter an optional scanner and comparison group.
4. Tap existing result rows to edit them, swipe to remove them, or use **Add result manually** for unsupported report layouts and regional measurements. Changing an entered unit does not convert its number: copy both as printed. Stored original units are retained; comparisons/CSV also provide canonical units.
5. Review all results and check **I checked the date, sites, units and every result against the report**. Only **Save** writes the record. For a previously shared scan, saving also updates its selected Health fields. A new scan requires a separate sharing review. Cancel requires confirmation and discards unsaved changes.

Importing a different PDF into a draft keeps previously entered values; reconcile them explicitly. The final review checkbox is cleared after changes to values or scan identity. Native UI interaction and this reset behaviour still need device testing.

### Automatic text extraction: intentionally limited

PDFKit reads selectable text locally. The rule-based parser recognizes **clear single-line metric/value pairs with explicit units**, for example:

```text
Total Body Fat %: 20.0%
Total Body Mass: 85.0 kg
Total Body Fat Mass: 17.0 kg
Total Body Lean Soft Tissue: 65.0 kg
Total Body Bone Mineral Content: 3,000 g
VAT Area: 55 cm2
Estimated RMR: 1750 kcal/day
```

These are synthetic examples, not your measurements. Generic labels such as `Total Mass` still require an anatomical site: “total” alone might refer to a region. A label explicitly saying “Total body” supplies that site as an editable candidate. Unqualified “lean mass” is recorded under **Lean mass · definition unconfirmed**, not silently mapped to lean soft tissue or fat-free mass.

**This is not a universal DEXA-table parser.** Multi-column tables, dates/history selection, regional table rows, missing/contradictory units, comma-decimal extracted text, image-only scans and screenshots are not automatically interpreted. View the PDF and manually add those values, or paste a clearly labelled transcription. There is **no OCR, screenshot import or AI-based report extraction** in this version. The existing photo estimator remains for food only; do not use it for scan reports.

Recognized repeated values are presented separately for review rather than guessed to be current. The importer does not combine regional totals, infer missing measurements or derive fat-free mass. Parser tests use synthetic text and one synthetic PDF fixture, not a validated set of provider reports. An actual provider report may require entirely manual entry.

PDF limits: 12 MiB per file, 1–30 pages, at most 100,000 extracted text characters. Protected PDFs must be unlocked locally before selection. Missing/unsupported text leaves the original viewable for manual transcription. Failed imports do not replace the current source or values. At most 100 results can be stored in each scan.

## What is recorded

Each result has a metric, explicit site/region, original number and unit, and—when imported—its original source line. Supported metrics are:

- Body-fat percentage, total mass, fat mass, lean soft tissue, fat-free mass and unspecified-definition lean mass.
- Bone mineral content; visceral-fat mass, area and volume as separate quantities; android/gynoid ratio.
- Bone mineral density, site-specific T-scores and Z-scores, and the report's resting-metabolic-rate figure.

Mass supports kg, lb and g. Area and volume support metric and imperial units. Density is g/cm². Enter `19` for `19%`. The field editor accepts signed scores and decimal point or comma, but no thousands separators; extracted English-formatted values can include unambiguous thousands grouping. Readouts retain up to four displayed decimal places; stored numeric values are not rounded by that display.

**This is a record of report values, not a diagnosis.** Lean soft tissue, fat-free mass and bone mineral content remain distinct. No reported lean measure is relabelled as “muscle gained.” No T-score/Z-score thresholds, bone-health classifications or treatment advice are generated. The input limits are broad typing checks, not healthy ranges.

## Trends and maintenance

Whole-body scan charts show individual scan points, not a daily fitted/interpolated curve. Regional results remain available in each scan. A comparison group is a manually assigned scanner/protocol label, independent of Home/Girlfriend’s weigh-in tags. Leave it blank when comparability is unclear.

When you open a scan, reported differences use the latest earlier scan with the **same comparison group, metric and site**. Unit conversion occurs without rewriting the original data. Body-fat differences use percentage points. Same-day conflicting prior scans and unspecified lean definitions do not receive a difference. Matching a group label does not verify scanner calibration or statistical significance; no significance claim is made.

**Importing a scan does not change the maintenance estimate, targets, scale baselines or previous readings.** DXA records are stored separately from `BodyMeasurement` and never enter the weight-fit or energy-balance calculation. A printed resting-metabolic-rate figure is retained as a report value, not substituted for total maintenance or measured expenditure. The existing within-scale maintenance engine and its guardrails are unchanged.

**Compatible whole-body values can now be shared with Apple Health after a separate per-scan review.** See [DEXA-HEALTH.md](DEXA-HEALTH.md) for selection, definitions, timestamp review, replacements and queued removals. Scan exports are excluded from Recomp’s scale-based maintenance model; no consumer scale is auto-calibrated. Existing ordinary weight/body-fat/waist and food Health integration is retained. There is no automatic adjustment based on a single scan or computed DXA-based body-composition energy model.

## Local retention, duplicates and exports

The source PDF is initially held in memory for review. **Keep a local copy of the PDF** is off by default on new imports. When enabled, the PDF is saved inside the existing atomic, protected diary file; all retained reports together are limited to 48 MiB. Keeping large PDFs increases diary size and save work. Full extracted/pasted text is discarded when the editor closes; accepted source lines, filename and a file fingerprint are stored alongside the reviewed results. Remove identifying text from pasted lines before accepting them when appropriate.

No scan content is sent to the photo server or an AI provider. The source in Files is not modified. A chosen Files provider may itself use cloud storage under its own settings; that is distinct from Recomp uploading your report.

The file's SHA-256 fingerprint prevents importing the exact same PDF into a second scan. Edit its existing record instead. Re-exported or modified PDFs have different hashes; the app cannot detect every duplicate or verify that a report belongs to you. Check provider, patient identity and date against the report before saving.

The scan list offers **Export scan values as CSV**. Each row retains the scan identity, provider/scanner/group, metric/site, original and canonical units, source filename and notes. It does not include full PDF bytes or source excerpts and is not a restore backup. A retained PDF can be viewed/exported separately from its detail screen. Removing a scan removes its retained copy from the diary, not from your original Files location. Deleting a shared scan queues removal of its own Recomp Health exports; other Health records are unchanged. See `DEXA-HEALTH.md`.

As before, the local diary is excluded from device backups. **Uninstalling loses scans, retained PDFs and other local app data.** Keep your original report elsewhere and export values/PDFs before uninstalling. There is no multi-device scan sync or import-from-CSV restore.

## Update and test

Use the **same development team and bundle identifier** and install over the existing app. Do not uninstall first. Existing schema 1–4 diaries migrate to **schema 5**, preserving food, measurement, scale, Health-queue and target histories; the new scan log starts empty. Older app versions reject schema 5, so do not downgrade over your only copy. Portable migration tests passed; native in-place upgrades remain unverified.

`Examples/DXA-synthetic.pdf` and `.txt` are clearly labelled synthetic fixtures. They are not bundled into the app's diary. Test them in a throwaway simulator installation, not your real log. The PDF contains eight parseable values plus deliberately unsupported lines. Expand the text disclosure and use **Find labelled values** after import. The synthetic date and clinic must be entered manually.

```sh
swift test
./scripts/check-store.sh
(cd Server && node --test)
# On macOS with Xcode; also compiles an unsigned simulator build:
./scripts/check.sh
```

## References

Reviewed September 18, 2026. These support framework choices and terminology, not validation of this app or scanner comparability:

- Apple PDFKit (PDFDocument, PDFPage and PDFView): https://developer.apple.com/documentation/pdfkit
- Apple native file importer and security-scoped access: https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)
- ISCD Adult Official Positions, body-composition reporting and cross-calibration: https://iscd.org/official-positions-2023/
- BodySpec, three-compartment terminology: https://learn.bodyspec.com/module/core/01-how-dexa-works
