# Near Ride Architecture

## Monorepo layout

```text
near-ride/
├─ app/
│  └─ lib/
│     ├─ main.dart
│     ├─ core/
│     │  ├─ config/
│     │  └─ network/
│     └─ features/
│        ├─ ai/
│        ├─ auth/
│        ├─ ble/
│        ├─ chat/
│        ├─ friends/
│        ├─ gps/
│        ├─ home/
│        ├─ profile/
│        └─ settings/
├─ server/
│  └─ app/
│     ├─ database.py
│     ├─ main.py
│     ├─ models/
│     ├─ routes/
│     └─ services/
│        └─ trajectory/
│           ├─ geohash.py
│           ├─ similarity.py
│           └─ analyzer.py
├─ tools/
│  ├─ flutter/_test_tab.dart
│  └─ gps/visualizer.py
└─ docs/
   ├─ ARCHITECTURE.md
   └─ API.md
```

## Runtime boundaries

There are two production runtimes:

1. Flutter mobile application under `app/`.
2. FastAPI backend under `server/`.

GPS trajectory analysis is part of the FastAPI service. `tools/` contains developer/offline utilities and must not be imported by production runtime code.

## Flutter responsibilities

```text
main.dart
  └─ home
     ├─ BLE
     ├─ chat
     └─ settings

features/
  ├─ auth       login / registration
  ├─ ble        scan / advertising
  ├─ chat       rooms / messages / image client
  ├─ friends    friend API
  ├─ gps        tracking / GPS API / background coordination
  ├─ profile    profile / avatar
  ├─ ai         backend AI client / settings info
  └─ settings   user-facing settings
```

Shared API configuration and WebSocket transport belong in `core/`. Feature code should depend on focused services instead of a catch-all user API facade.

## Backend responsibilities

```text
FastAPI
├─ routes/
│  ├─ user_routes.py
│  ├─ friend_routes.py
│  ├─ chat_routes.py
│  ├─ gps_routes.py
│  ├─ hobby_routes.py
│  ├─ image_routes.py
│  └─ ai_routes.py
├─ models/                  SQLAlchemy models
├─ database.py              engine/session/bootstrap
└─ services/
   ├─ connection_manager.py
   ├─ avatar_service.py
   └─ trajectory/
```

FastAPI startup uses the application lifespan to create tables and initialize default hobbies.

## Client/server data flow

```text
Flutter
  ├─ REST ----------------------┐
  ├─ WebSocket /ws ------------┤
  ├─ BLE (device-local)         │
  └─ native GPS                 │
                               ▼
FastAPI
  ├─ SQLAlchemy -> database
  ├─ image/avatar storage
  ├─ Gemini proxy
  └─ trajectory matching
```

## AI boundary

All Gemini credentials are server-side.

```text
Flutter -> /ai/generate
        -> /ai/summarize
        -> /ai/emotion
        -> /ai/avatar
                    -> Gemini
```

The Flutter app must never package `secret.json` or persist provider credentials.

## GPS boundary

All persisted location data uses the backend `gps_locations` model. The legacy-compatible `POST /gps/upload` endpoint normalizes route points into the same table as `POST /gps/location`.

```text
GPS point(s) -> FastAPI -> gps_locations
                       -> trajectory analyzer
                          ├─ geohash
                          ├─ distance
                          ├─ DTW
                          └─ hybrid
```

Trajectory services receive prepared location data and do not create an independent database connection.

## Images and avatars

When Cloudinary is enabled, images are stored in Cloudinary. Otherwise development fallback files are written under `server/uploads/`, which is ignored by Git.

## Refactor rules

1. Keep one Flutter app and one FastAPI backend.
2. Organize Flutter by feature; keep cross-feature infrastructure in `core/`.
3. Keep database access in FastAPI.
4. Keep tools outside production runtime directories.
5. Keep secrets server-side.
6. Prefer one canonical implementation for each responsibility.
7. Do not merge `refactor/near-ride-monorepo` into `main` until explicitly approved.
