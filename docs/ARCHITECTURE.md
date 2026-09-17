# Near Ride Architecture

## Repository layout

```text
near-ride/
├─ app/                         Flutter production app
├─ server/                      FastAPI backend and runtime services
│  └─ app/services/trajectory/
│     ├─ geohash.py
│     ├─ similarity.py
│     └─ analyzer.py
├─ tools/
│  ├─ flutter/
│  │  └─ _test_tab.dart        Developer-only Flutter diagnostics
│  └─ gps/
│     └─ visualizer.py         Offline GPS visualization/reporting
└─ docs/
```

## Runtime boundaries

The Flutter release app must not import developer utilities from `tools/`.
The FastAPI runtime must not depend on matplotlib or folium.
GPS visualization is intentionally separated from trajectory matching.

## Data flow

```text
Flutter
  ├─ BLE
  ├─ GPS collection
  ├─ Chat / WebSocket
  └─ Profile
       │
       ▼
FastAPI
  ├─ REST API
  ├─ WebSocket
  ├─ PostgreSQL / SQLAlchemy
  └─ Trajectory service
       ├─ Geohash
       ├─ Distance
       ├─ DTW
       └─ Hybrid score
```

## Refactor principles

1. One Flutter app, one backend service.
2. Database access stays in FastAPI; trajectory algorithms receive prepared route data.
3. Developer/test utilities live under `tools/` and are not part of production navigation.
4. Secrets are server-side; Flutter must not package API-key files such as `assets/secret.json`.
5. Prefer small modules with one responsibility instead of large multipurpose service files.
