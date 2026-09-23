# Near Ride API Reference

This document reflects the FastAPI routes currently registered by `server/app/main.py`.

## Service

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | Service status |
| GET | `/health` | Health endpoint |

FastAPI also exposes its generated OpenAPI/Swagger documentation when enabled by the framework defaults, typically at `/docs`.

## Users

Mounted under `/users`.

| Method | Path | Purpose |
|---|---|---|
| POST | `/users/` | Register user |
| POST | `/users/login` | Login |
| GET | `/users/{user_id}` | Get profile |
| PUT | `/users/{user_id}` | Replace/update profile fields |
| PATCH | `/users/{user_id}` | Partially update profile |
| POST | `/users/{user_id}/avatar` | Upload avatar from base64 |
| DELETE | `/users/{user_id}/avatar` | Remove avatar |

Profile GET and login responses include `commute_modes`, a list of 汽車、機車、
公車、捷運、火車. Profile PATCH/PUT accepts
`{"commute_modes":["捷運","公車"]}`; `[]` clears all and omission leaves
current selections unchanged. Selected modes use a new
`user_commute_modes` table created on backend startup.

## Friends and chat history

Mounted under `/friends`.

| Method | Path | Purpose |
|---|---|---|
| POST | `/friends/add_friend` | Add friend and ensure direct room |
| GET | `/friends/friends/{user_id}` | List friends |
| DELETE | `/friends/remove_friend` | Remove friend |
| GET | `/friends/chat_history/{room_id}` | Get room history |

## Friend recommendations

Mounted under `/friends`. Users are excluded from recommendation results unless
they have explicitly enabled participation. Only one matched profile is returned
per request; neither coordinates nor full GPS routes are returned.

| Method | Path | Purpose |
|---|---|---|
| GET | `/friends/recommendation-settings/{user_id}` | Read opt-in preference |
| PUT | `/friends/recommendation-settings/{user_id}` | Set `{"enabled": true/false}` |
| GET | `/friends/recommendation/{user_id}` | Return one matched profile or a reason for no match |

The recommendation GET accepts repeated `exclude_user_ids` query parameters so
the client can skip already viewed candidates. It excludes the current user and
existing friends, requires at least eight recent points from each party, and
compares tracks from the last 14 days. Shared commute mode + GPS route/time
of day similarity takes first priority. The response includes
`commute_modes` and `shared_commute_modes` without disclosing exact
coordinates or times. These are *general GPS tracks*: the
current database does not yet tag commute sessions. See
`docs/FRIEND_RECOMMENDATIONS.md` for testing and privacy limitations.

A second compatibility history endpoint remains available:

| Method | Path | Purpose |
|---|---|---|
| POST | `/chat_history` | Fetch history using a `roomId` request body |

## WebSocket

| Protocol | Path | Purpose |
|---|---|---|
| WebSocket | `/ws` | User registration, room join/leave, messaging, BLE connection requests |

Current message types handled by the gateway include:

- `register_user`
- `create_room`
- `join_room`
- `leave_room`
- `message`
- `connect_request`
- `connect_response`

Users must register on the socket before other message types are processed. Chat messages are rejected when the target room does not exist.

## GPS

| Method | Path | Purpose |
|---|---|---|
| POST | `/gps/location?user_id={id}` | Store one location point |
| POST | `/gps/upload` | Compatibility route upload; points are normalized into `gps_locations` |
| GET | `/gps/locations/{user_id}` | Query recorded locations |
| GET | `/gps/locations/{user_id}/date/{date_text}` | Query one date |
| DELETE | `/gps/locations/{user_id}` | Delete recorded locations |
| GET | `/gps/similar/{user_id}` | Find similar recent trajectories |

Trajectory methods accepted by `/gps/similar/{user_id}`:

- `geohash`
- `distance`
- `dtw`
- `hybrid`

## Hobbies

| Method | Path | Purpose |
|---|---|---|
| GET | `/hobbies` | List hobbies |
| POST | `/hobbies` | Create hobby |
| POST | `/hobbies/initialize` | Initialize default hobbies |

Default hobbies are also initialized during FastAPI lifespan startup.

## Images

| Method | Path | Purpose |
|---|---|---|
| POST | `/images/upload` | Upload and normalize chat image |
| GET | `/images/{image_id}` | Read/redirect an image |

When Cloudinary is disabled, development images are stored under `server/uploads/`.

## AI

| Method | Path | Purpose |
|---|---|---|
| POST | `/ai/generate` | Generate assistant text |
| POST | `/ai/summarize` | Summarize conversation |
| POST | `/ai/emotion` | Analyze message emotion |
| POST | `/ai/avatar` | Generate avatar image |

Gemini credentials are read from server environment variables and are never supplied by the Flutter client.

## Configuration

Flutter endpoints are centralized in `app/lib/core/config/api_config.dart` and may be overridden with:

```bash
--dart-define=API_URL=https://your-api.example.com
--dart-define=WS_URL=wss://your-api.example.com
```

Server configuration is documented in `server/.env.example`.
