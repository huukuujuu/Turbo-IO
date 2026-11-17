# Korean personal build

Based on upstream commit 28a0fef0a42773f38222fcd0db2e0f2852ed4257.
The phone app's navigation, controls, help, and consent labels are translated to Korean.
Original SDK development logs remain in Chinese; app-visible diagnostics are summarized in Korean.
No firmware changes or automatic pairing are included.

`ko.tsv` holds exact string translations; `fragments.tsv` covers interpolated view text.
`python3 localizations/apply_ko.py` reapplies these source translations.
Selection tags and saved model settings retain their original values.
The device XcodeGen specification sets Korean permission descriptions and build 5.

Build with the existing `project-device.yml`, `RayNeoCompanionDevice` scheme,
and your own development team. Keep the existing bundle identifier and signing
team when updating to preserve the app container and keychain access.

Validation: device build succeeded; code signature verified; selection tags,
accessibility identifiers, and credential/storage source unchanged.

## Full review, 2026-11-18

Runtime status/error strings and export text are now covered by `ko-review.tsv`
and `review-fragments.tsv`. Run `python3 localizations/audit_ko.py` to check
app-owned UI strings. The only source exceptions are legacy selection/storage
values. Existing user content is not translated. SDK logs are localized at the
UI boundary by `KoreanDiagnostics`; original development logs stay intact.

Build 4 adds the external-service guide and labels the generic model screen as
a save-only draft. Validation: 217 unit tests and one UI walkthrough passed;
six UI screenshots were visually reviewed. Live external APIs were not called.

## Service diagnostics, build 5

DeepSeek HTTP failures now include their status and an actionable Korean explanation
(authentication, balance, request format, throttling, or service failure). Network
errors expose only their numeric code. A separate connection test uses a fixed
short sentence and reads the balance associated with the same stored key, without
recording microphone audio or sending text to the glasses. API keys and server
error bodies are never logged. Test results remain visible in the conversation UI.

Device build, code signing, installation, and the HTTP 402 failure path were
verified. A successful paid model response and end-to-end glasses rendering still
require separate validation with an account that has available API balance.

## Git history

This fork preserves upstream history. `upstream` points to Turbo1123/Turbo-IO;
`origin` points to the personal fork. Korean customization lives on
`ko/ios-personal`. See `docs/ko/CHANGELOG.md` for the saved baseline, validation,
and feature boundaries. Keep keys, signing assets, raw logs, and generated builds
outside commits. After a change, run the Korean audit and relevant checks before
committing and pushing the customization branch.
