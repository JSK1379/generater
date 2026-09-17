# Near Ride Flutter App

Flutter client for Near Ride. The app handles BLE discovery/advertising, account setup, chat, optional GPS tracking, profile/avatar UI, and settings.

## Run

```bash
flutter pub get
flutter run
```

Backend URLs can be overridden at build/run time:

```bash
flutter run \
  --dart-define=API_URL=https://your-api.example.com \
  --dart-define=WS_URL=wss://your-api.example.com
```

## Source layout

```text
lib/
├─ main.dart
├─ main_tab_page.dart            # app shell/navigation
├─ core/
│  ├─ config/
│  ├─ network/
│  └─ compat/                    # temporary compatibility facades
└─ features/
   ├─ ai/
   ├─ auth/
   ├─ ble/
   ├─ chat/
   ├─ gps/
   ├─ profile/
   └─ settings/
```

Most small files still visible directly under `lib/` are compatibility exports for older imports. New code should import from `core/` or `features/` instead.

## AI security

The Flutter app does **not** store Gemini credentials. Text and avatar generation are sent to the FastAPI backend under `/ai/*`; `GEMINI_API_KEY` is configured only in the server environment.

Do not add `assets/secret.json`, `.env`, API keys, database credentials, or cloud credentials to the mobile app.

## GPS

GPS API/model code lives under `features/gps/`. Background tracking is coordinated through `GpsTracker` and the enhanced foreground location service. The Android native foreground-service implementation remains under `android/` because it is platform code.

## Notes

- Package name: `near_ride`
- Flutter/Dart SDK: see `pubspec.yaml`
- Developer-only experiments belong in the repository-level `tools/` directory, not production `lib/`.
- Monorepo-level setup, backend instructions, deployment, and architecture are documented in the repository root README and `docs/`.
