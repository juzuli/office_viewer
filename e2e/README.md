# End-to-end tests

This project is Flutter/mobile, not a web app — Playwright does not apply.

| Path | What |
| --- | --- |
| `test/e2e_flows_test.dart` | Host flow specs (FakeOfficeEngine) — same cases as `e2e/f01_controller_flows_test.dart` |
| `example/integration_test/viewer_smoke_test.dart` | Device smoke (F01/F02) against PDF example |
| `example/test/fake_fallback_banner_test.dart` | F01-N1 fake-engine banner |

```bash
# Host
flutter test test/

# Android device
cd example && flutter test integration_test/viewer_smoke_test.dart -d <device-id>

# iOS device
cd example && flutter test integration_test/viewer_smoke_test.dart -d <device-id>
```
