# Near Ride Flutter App

Flutter client for Near Ride. It handles BLE discovery/advertising, account setup, chat, GPS tracking, profile/avatar UI, AI integration, and settings.

## Run

```bash
flutter pub get
flutter run
```

Optional backend overrides:

```bash
flutter run \
  --dart-define=API_URL=https://your-api.example.com \
  --dart-define=WS_URL=wss://your-api.example.com
```

## Source layout

```text
lib/
├─ main.dart
├─ core/
│  ├─ core.dart
│  ├─ config/
│  │  └─ api_config.dart
│  └─ network/
│     └─ websocket_service.dart
└─ features/
   ├─ features.dart
   ├─ ai/
   ├─ auth/
   ├─ ble/
   ├─ chat/
   ├─ friends/
   ├─ gps/
   ├─ home/
   ├─ profile/
   └─ settings/
```

Each feature owns its pages, services, models, or utilities. `features/home/pages/main_tab_page.dart` contains the main app shell/navigation. There are no legacy compatibility export files at the `lib/` root.

## Default backend

The app's default REST and WebSocket endpoints target the new Render test service:

```text
https://near-ride-refactor-api.onrender.com
wss://near-ride-refactor-api.onrender.com/ws
```

Confirm the public URL shown in the Render service dashboard before installing the app. Build-time `API_URL` and `WS_URL` overrides take precedence over these defaults. The newly deployed backend must be used for the GPS friend recommendation routes.

## Developer TEST tab

The manual Flutter/WebSocket/GPS test page lives under `lib/features/dev/` and is hidden by default. To expose it while loading the app onto a test phone:

```bash
flutter run --dart-define=ENABLE_DEV_TOOLS=true
```

Normal builds omit the TEST tab from navigation.

## Networking

Shared backend configuration lives in `core/config/api_config.dart`; the canonical WebSocket implementation lives in `core/network/websocket_service.dart`.

## AI security

The Flutter app does not store Gemini credentials. Text and avatar generation call FastAPI under `/ai/*`; `GEMINI_API_KEY` is configured only in the server environment.

Do not add `assets/secret.json`, `.env`, API keys, database credentials, or cloud credentials to the mobile app.

## GPS

GPS code lives under `features/gps/`. `GpsTracker` is the app-level tracking entrypoint, while `BackgroundGPSService` and `EnhancedForegroundLocationService` implement background/native coordination. Android native foreground-service code remains under `android/`.

## Notes

- Dart package: `near_ride`
- Dart SDK constraint: `>=3.7.0 <4.0.0`
- Developer-only experiments belong in repository-level `tools/`
- Backend/deployment documentation is maintained in the repository root and `docs/`
