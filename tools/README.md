# Developer Tools

This directory contains development-only utilities that are intentionally kept outside production runtime code.

- `flutter/_test_tab.dart`: manual Flutter/WebSocket/GPS test UI. It is not imported by the production app.
- `gps/visualizer.py`: offline GPS trajectory visualization/report tooling. It is not imported by the FastAPI runtime.

Keep production code inside `app/` and `server/`; keep experiments, diagnostics, and visualizers here.
