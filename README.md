# Near Ride

Near Ride is a monorepo containing the Flutter client, FastAPI backend, GPS trajectory matching, and developer tools.

## Project layout

```text
near-ride/
├─ app/                         Flutter app
│  └─ lib/
│     ├─ main.dart              application entrypoint
│     ├─ core/
│     │  ├─ config/             API / WebSocket configuration
│     │  └─ network/            shared networking
│     └─ features/
│        ├─ ai/
│        ├─ auth/
│        ├─ ble/
│        ├─ chat/
│        ├─ friends/
│        ├─ gps/
│        ├─ home/               app shell/navigation
│        ├─ profile/
│        └─ settings/
├─ server/                      FastAPI backend
│  └─ app/
│     ├─ models/
│     ├─ routes/
│     └─ services/
│        └─ trajectory/         geohash / distance / DTW / hybrid matching
├─ tools/
│  ├─ flutter/_test_tab.dart    developer-only diagnostics
│  └─ gps/visualizer.py         offline trajectory visualization
├─ docs/
│  ├─ ARCHITECTURE.md
│  └─ API.md
└─ render.yaml
```

## Flutter app

```bash
cd app
flutter pub get
flutter run
```

Backend URLs can be overridden without editing source code:

```bash
flutter run \
  --dart-define=API_URL=https://your-api.example.com \
  --dart-define=WS_URL=wss://your-api.example.com
```

The Dart package name is `near_ride`. Production code is organized under `core/` and `features/`; `app/lib/main.dart` is the only Dart file kept at the library root.

## FastAPI backend

```bash
cd server
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

If `DATABASE_URL` is not set, the backend uses local SQLite for development. Production should use PostgreSQL.

## Server environment variables

Copy `server/.env.example` to `server/.env` for local development.

```env
DATABASE_URL=postgresql://USER:PASSWORD@HOST:5432/DBNAME
USE_CLOUD_STORAGE=false
CLOUDINARY_URL=
GEMINI_API_KEY=
GEMINI_MODEL=gemini-2.0-flash
GEMINI_IMAGE_MODEL=gemini-2.0-flash-preview-image-generation
```

Never commit `.env`, `secret.json`, API keys, database passwords, cloud credentials, or runtime uploads.

## Runtime architecture

Near Ride has two production runtimes:

1. Flutter under `app/`.
2. FastAPI under `server/`.

GPS trajectory matching is an internal FastAPI service, not a third runtime. Developer tools under `tools/` are outside production runtime paths.

### GPS

```text
Flutter GPS -> FastAPI GPS routes -> SQLAlchemy -> gps_locations
                                   -> trajectory analyzer
                                      ├─ geohash
                                      ├─ distance
                                      ├─ DTW
                                      └─ hybrid
```

Similarity endpoint:

```http
GET /gps/similar/{user_id}?method=hybrid&threshold=0.3&days=7
```

### AI

Gemini credentials stay on the server.

```text
Flutter -> POST /ai/generate   -> Gemini text
Flutter -> POST /ai/summarize  -> Gemini text
Flutter -> POST /ai/emotion    -> Gemini text
Flutter -> POST /ai/avatar     -> Gemini image
```

## API reference

See `docs/API.md` for the current FastAPI and WebSocket surface.

## Deployment

`render.yaml` deploys `server/` using:

```text
uvicorn app.main:app --host 0.0.0.0 --port $PORT
```

Database, Cloudinary, and Gemini credentials are configured as environment variables.

## Refactor branch

All consolidation work remains isolated in:

```text
refactor/near-ride-monorepo
```

Do not merge this branch into `main` until explicitly approved. Flutter and backend runtime smoke tests are still required before merge; structural/static checks do not replace running the applications.
