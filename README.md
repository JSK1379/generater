# Near Ride

Near Ride is now organized as a single monorepo containing the Flutter client,
FastAPI backend, GPS trajectory matching, and developer tools.

## Project layout

```text
near-ride/
├─ app/                         Flutter mobile app
│  └─ lib/
│     ├─ core/                  shared configuration/network code
│     └─ features/              feature-oriented modules
├─ server/                      FastAPI backend
│  └─ app/
│     ├─ models/
│     ├─ routes/
│     └─ services/
│        └─ trajectory/         Geohash / distance / DTW / hybrid matching
├─ tools/
│  ├─ flutter/_test_tab.dart    developer-only Flutter test screen
│  └─ gps/visualizer.py         offline trajectory visualization
├─ docs/
└─ render.yaml
```

## Flutter app

```bash
cd app
flutter pub get
flutter run
```

The production backend can be overridden without editing source code:

```bash
flutter run \
  --dart-define=API_URL=https://your-api.example.com \
  --dart-define=WS_URL=wss://your-api.example.com
```

Developer-only utilities under `tools/` are intentionally not imported by the
production app.

## FastAPI backend

```bash
cd server
python -m venv .venv
# Windows: .venv\Scripts\activate
# macOS/Linux: source .venv/bin/activate
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Default local API: `http://127.0.0.1:8000`

If `DATABASE_URL` is not set, the backend falls back to a local SQLite database
for development. Production should use PostgreSQL.

## Server environment variables

Copy `server/.env.example` to `server/.env` for local development and fill in
only the values you need.

```env
DATABASE_URL=postgresql://USER:PASSWORD@HOST:5432/DBNAME
USE_CLOUD_STORAGE=false
CLOUDINARY_URL=
GEMINI_API_KEY=
GEMINI_MODEL=gemini-2.0-flash
```

Never commit `.env`, `secret.json`, API keys, database passwords, or Cloudinary
credentials.

## GPS architecture

The mobile app records GPS points through the FastAPI service. All persisted
GPS points use the same `gps_locations` table.

Trajectory matching lives inside the backend:

```text
server/app/services/trajectory/
├─ geohash.py
├─ similarity.py
└─ analyzer.py
```

Available algorithms are `geohash`, `distance`, `dtw`, and `hybrid`.

Example endpoint:

```http
GET /gps/similar/{user_id}?method=hybrid&threshold=0.3&days=7
```

Visualization is a development tool only and stays at
`tools/gps/visualizer.py`; FastAPI does not depend on matplotlib or folium at
runtime.

## AI architecture

Gemini credentials are server-managed. The Flutter app never stores the Gemini
API key. AI traffic flows as:

```text
Flutter -> FastAPI /ai/* -> Gemini API
```

Configure `GEMINI_API_KEY` only in the server environment.

## Deployment

`render.yaml` deploys only the `server/` directory as the backend service.
Database, Cloudinary, and Gemini credentials are configured as Render
environment variables rather than committed files.

## Current refactor branch

Development for the monorepo migration is isolated in:

```text
refactor/near-ride-monorepo
```

Do not merge into `main` until the Flutter and backend smoke tests pass.
