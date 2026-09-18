# Developer Tools

This directory contains repository-level development utilities that are outside production runtime code.

- `gps/visualizer.py`: offline GPS trajectory visualization/report tooling. It is not imported by the FastAPI runtime.

The Flutter test UI now lives inside the Flutter package at:

```text
app/lib/features/dev/pages/test_tab.dart
```

It is hidden by default. To expose the TEST tab on a device during development:

```bash
cd app
flutter run --dart-define=ENABLE_DEV_TOOLS=true
```

Keep production application code inside `app/`, backend code inside `server/`, and repository-level offline utilities inside `tools/`.
