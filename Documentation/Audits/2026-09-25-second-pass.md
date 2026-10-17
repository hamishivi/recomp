# Second audit — September 25, 2026

## Fixes

- **Unauthenticated Wi-Fi diary exchange:** merely opening Sync & Storage previously advertised a plaintext service that accepted and replied with complete diary data without pairing. Pairing is now explicitly started with a shared, temporary 256-bit random code. Requests and responses use CryptoKit AES-GCM with a fresh server challenge and direction-specific authenticated data. Wrong-code, modified, reflected and replayed packets are rejected before decoding or merging state. The new Bonjour service does not interoperate with the old plaintext protocol. Update both devices before syncing.
- **Sync lifecycle and framing:** only one exchange runs at a time, a 30-second timeout bounds stalled connections, stopping pairing cancels incoming and outgoing work, and delayed callbacks verify session ownership. Frame lengths are bounded and decoded without assuming aligned memory; reads use bounded chunks rather than recursive accumulation. Pairing codes are cleared when the screen closes and are not persisted.
- **Silent merge failure:** invalid combined states now return an explicit failure instead of returning the original state and reporting success. Conflicting independently-created scale names are an example; reconcile those names before retrying.
- **Stale calorie targets after sync:** target changes are compared by their timestamps rather than the number of revisions on each device. An older but longer history cannot overwrite a newer target.
- **Lost body edits:** the higher measurement version now wins during merge, matching the existing versioned edit system.
- **Stale maintenance confirmations after sync:** changed food dates, amounts, estimation flags or diary clocks invalidate the affected confirmations from both replicas. Cached maintenance history is cleared after food changes. Users must review those days again; unknown food completeness is not inferred from a merged log.
- **Storage switch failure:** a destination is read and validated before replacing the active diary, active file or storage preference. A corrupt destination leaves the original diary writable. Switching during an active Health read/sync is rejected, and cached Health data is cleared on successful switching.
- **Missed external writes:** successful saves record their modification time; external changes less than one second later are no longer ignored. A file appearing after an initially empty load can also be detected. An unavailable iCloud location no longer falls back to an invented local path labelled as iCloud.
- **Travel averages:** the seven-day intake summary uses saved diary date labels consistently and excludes future actual meal timestamps.
- **Misleading weight summaries:** daily medians from a single scale/source are used for comparisons. Same-day fluctuations no longer become weekly changes, excluded local readings cannot be replaced by imported readings from the same scale/day, and old readings are not displayed as a recent net change. The Trends net-change label no longer mixes weight with waist/body-fat measurements or different scales.

## Pairing workflow

Open **Settings → Sync & Storage** on both devices. Create a pairing code on one device and privately copy/share it to the other. Start pairing on both devices and select Sync Now on one. The code grants diary-sync access while pairing is active; share it only with your other device. Stop pairing or leave the screen to end the session. Existing encrypted backup export remains available independently.

A paired exchange is not an atomic distributed transaction: if a connection breaks after the receiver commits but before the response arrives, the sender may need to retry. IDs and versions prevent duplicate food entries. The protocol has not had an independent cryptographic review; it uses platform cryptography rather than a custom cipher.

## Validation

Regression tests cover saved travel dates, future food, same-day weight readings, mixed body metrics, exclusions, invalid merges, versioned measurement edits, review invalidation from either merge direction, corrupt storage destinations and rapid external writes.

The macOS transport harness uses the production Wi-Fi service over loopback TCP with synthetic diaries, bypassing Bonjour discovery. It checks authenticated wrong-code rejection, matching-code exchange and cancellation of a stalled incoming transfer. CryptoKit tests separately check tampering, wrong direction, fresh-challenge replay rejection, malformed packets and invalid pairing keys. Bonjour discovery and a physical iPhone-to-Mac exchange still need real-device verification.

Final verification completed successfully:

- 420 core tests passed in Debug and Release after the final changes.
- The broad portable sweep passed all coordinator/source/network harnesses and 68 server tests. The final target-recency adjustment was then rechecked by both core configurations and the native gate.
- The persistence audit passed all 32 checks.
- The production encrypted loopback transport passed wrong-code, matching-code and incoming-cancellation checks.
- 425 native unit tests and all 13 UI tests passed with Xcode 27.0 / iOS 27.0 Simulator.
- The native Release app/widget build succeeded; the final command pipeline exited 0.

Logs: [verification directory](../../Verification/Second-Audit-2026-09-25/). Native result bundle and screenshot attachments: `.native-results/20260925-180124-24010/`.

Xcode's optional simulator diagnostics collector stalled after all tests completed. Only that collector was terminated; Xcode subsequently reported TEST SUCCEEDED and completed the Release build successfully. Some optional simulator diagnostics may therefore be absent.

Only synthetic diary data and freshly generated test pairing codes were used in transport tests.

Simulator logs still contain pre-existing “Invalid frame dimension” warnings during some food-sheet transitions (also present in the first audit). Their layout source has not been isolated; passing functional UI tests does not establish that every transient layout is correct.
