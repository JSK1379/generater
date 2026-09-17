# Near Ride Architecture

## Monorepo layout

```text
near-ride/
├─ app/                         Flutter production app
│  └─ lib/
│     ├─ main.dart
│     ├─ main_tab_page.dart     App shell/navigation
│     ├─ core/
│     │  ├─ config/
│     │  ├─ network/
│     │  └─ compat/             Temporary compatibility facades
│     └─ features/
│        ├─ ai/
│        ├─ auth/
│        ├─ ble/
│        ├─ chat/
│        ├─ gps/
│        ├─ profile/
│        └─ settings/
├─ server/                      FastAPI backend
│  └─ app/
│     ├─ models/
│     ├─ routes/
│     └─ services/
│        └─ trajectory/
│           ├─ geohash.py
│           ├─ similarity.py
│           └─ analyzer.py
├─ tools/
│  ├─ flutter/_test_tab.dart    Developer-only diagnostics
│  └─ gps/visualizer.py         Offline GPS visualization
└─ docs/
```

## Runtime boundaries

Near Ride has two production runtimes:

1. Flutter mobile application under `app/`.
2. FastAPI backend under `server/`.

GPS trajectory matching is an internal FastAPI service, not a third standalone application. Developer tools under `tools/` are never imported by the production Flutter or FastAPI runtime.

## Client data flow

```text
Flutter
  ├─ BLE discovery / advertising
  ├─ Auth / profile
  ├─ GPS collection
  ├─ Chat / WebSocket
  └─ AI UI
       │
       ▼
FastAPI
  ├─ REST API
  ├─ WebSocket
  ├─ SQLAlchemy database layer
  ├─ AI proxy
  └─ Trajectory service
```

## AI boundary

All provider credentials stay on the server.

```text
Flutter -> /ai/generate   -> Gemini text model
Flutter -> /ai/summarize  -> Gemini text model
Flutter -> /ai/emotion    -> Gemini text model
Flutter -> /ai/avatar     -> Gemini image model
```

The Flutter app must never package `secret.json` or persist Gemini credentials locally.

## GPS boundary

The Flutter app records location points through the FastAPI GPS routes. Database access remains inside FastAPI/SQLAlchemy. Trajectory algorithms receive prepared route points and do not open independent database connections.

```text
GPS points -> FastAPI -> database
                     -> trajectory analyzer
                        ├─ geohash
                        ├─ distance
                        ├─ DTW
                        └─ hybrid
```

`tools/gps/visualizer.py` is offline tooling and is intentionally excluded from server runtime dependencies.

## Flutter migration rule

Files directly under `app/lib/` other than `main.dart` and `main_tab_page.dart` are temporary compatibility exports for legacy imports. New code should import the canonical implementation from `core/` or `features/`.

Compatibility exports can be removed only after all internal imports have been migrated and Flutter analysis/tests pass.

## Refactor principles

1. One Flutter app and one backend service.
2. Organize Flutter code by feature and backend code by route/model/service responsibility.
3. Keep database access in FastAPI.
4. Keep developer/test utilities outside production runtime directories.
5. Keep secrets server-side.
6. Prefer one canonical implementation per responsibility; legacy root files should only re-export during migration.
7. Do not merge `refactor/near-ride-monorepo` into `main` until the refactor is explicitly approved.
