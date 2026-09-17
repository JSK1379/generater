# Near Ride

Near Ride is organized as a single monorepo containing the Flutter client, FastAPI backend, GPS trajectory matching, and developer tools.

## Project layout

```text
near-ride/
├─ app/                         Flutter mobile app
│  └─ lib/
│     ├─ main.dart
│     ├─ main_tab_page.dart     app shell/navigation
│     ├─ core/                  shared config/network/compat code
│     └─ features/              auth, BLE, chat, GPS, profile, AI, settings
├─ server/                      FastAPI backend
│  └─ app/
│     ├─ models/
│     ├─ routes/
│     └─ services/
│        └─ trajectory/         geohash / distance / DTW / hybrid matching
├─ tools/
│  ├─ flutter/_test_tab.dart    developer-only Flutter diagnostics
│  └─ gps/visualizer.py         offline trajectory visualization
├─ docs/
│  └─ ARCHITECTURE.md
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

Legacy files directly under `app/lib/` are temporary compatibility exports. New code should import from `core/` or `features/`.

## FastAPI backend

```bash
cd server
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

If `DATABASE_URL` is not set, the backend falls back to a local SQLite database for development. Production should use PostgreSQL.

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

Never commit `.env`, `secret.json`, API keys, database passwords, or cloud credentials.

## GPS architecture

The mobile app records GPS points through FastAPI. Trajectory matching is an internal backend service:

```text
server/app/services/trajectory/
├─ geohash.py
├─ similarity.py
└─ analyzer.py
```

Supported matching methods are `geohash`, `distance`, `dtw`, and `hybrid`.

Example endpoint:

```http
GET /gps/similar/{user_id}?method=hybrid&threshold=0.3&days=7
```

Visualization remains developer-only under `tools/gps/` and is not a FastAPI runtime dependency.

## AI architecture

Gemini credentials are server-managed. Flutter never stores the Gemini API key.

```text
Flutter -> FastAPI /ai/generate  -> Gemini text
Flutter -> FastAPI /ai/summarize -> Gemini text
Flutter -> FastAPI /ai/emotion   -> Gemini text
Flutter -> FastAPI /ai/avatar    -> Gemini image generation
```

## Deployment

`render.yaml` deploys the `server/` directory. Database, Cloudinary, and Gemini credentials are configured as environment variables rather than committed files.

## Refactor branch

All monorepo/refactor work is isolated in:

```text
refactor/near-ride-monorepo
```

This branch must not be merged into `main` until explicitly approved. Flutter and backend runtime smoke tests are still required before merge; repository-level structural checks are not a substitute for running the apps.
