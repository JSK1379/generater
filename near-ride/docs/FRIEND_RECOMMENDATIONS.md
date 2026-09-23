# GPS friend recommendation — first test version

## What it does

Flutter now has a **推薦** tab between chat and settings. It displays **one**
eligible recommended person at a time, including nickname, avatar, optional
age/gender, commute modes and hobby names. The person can be skipped with **下一位**.
**發送連接邀請** uses the existing WebSocket connect-request flow and does not
guarantee delivery to an offline person.

Users must opt in with **參與好友推薦** to request recommendations and to be
eligible for other people's results. The server excludes the requester and
existing friends. Recommendation responses omit email, raw GPS coordinates,
route points, and exact origin/destination.

## Current matching rule

The API checks up to 120 of each user's most recent GPS points within the
past 14 days, requires at least 8 points per user, and uses the existing
hybrid trajectory comparison. It returns the eligible candidate with the
highest-ranked qualifying candidate, or a reason if no candidate qualifies.

Profiles offer a multi-select commute-mode field (汽車、機車、公車、捷運、火車).
The server stores selections in the new `user_commute_modes` table so the
existing PostgreSQL `users` table needs no ALTER TABLE. Profile PATCH accepts
`commute_modes` as a list; an empty list removes previous selections.
Candidates are ordered by **shared mode + similar GPS route AND daily time
window**, then shared mode + similar route, then similar route/time, then GPS
route similarity alone. The existing hybrid similarity score breaks ties
within each tier. Daily time proximity requires multiple samples at the same
clock time (+/-30 minutes) and within 300 metres on any date in the 14-day
window. This is an approximation using recorded clock hours: existing GPS
locations do not mark commute sessions and timezone normalization is not
consistent across legacy data. No exact clock time, coordinate, or full route
is returned to the client.

**Limitation:** `gps_locations` currently contains general GPS recordings,
not explicitly labelled commute trips. Matching is therefore a *recent GPS
trajectory similarity estimate*, not a validated commute overlap or proof
that users travel at the same time. Commute tagging and trip segmentation
should precede claims about commuting compatibility.

## Manual phone test

1. Deploy or run the backend **from this refactor branch**, not the previous
   deployed backend; the API and the new `recommendation_preferences` table
   must exist. The backend creates the new table during lifespan startup.
2. Prepare two separate test accounts, record at least 8 recent GPS points
   per account on comparable routes, and make sure they are not already friends.
   In each profile, select one or more commute modes below 居住地, save and
   reopen the editor to confirm that the selections persist.
3. Run the Flutter app from `near-ride/app` and open **推薦**. Enable participation
   on **both accounts**.
4. Compare a shared-mode and overlapping-time candidate with a different-mode
   candidate. Verify the shared-mode/overlapping-time candidate comes first,
   and that the card shows commute modes. Confirm the screen displays one
   person, **下一位** skips that person, and
   disabling participation removes the profile. Test the no-GPS and no-match
   messages as well.

Example local commands (run backend and app in separate terminals):

```bash
cd near-ride/server
uvicorn app.main:app --reload
```

```bash
cd near-ride/app
flutter run --dart-define=API_URL=http://YOUR_LAN_IP:8000 --dart-define=WS_URL=ws://YOUR_LAN_IP:8000
```

Replace `YOUR_LAN_IP` with the computer's reachable LAN address. Android
cleartext HTTP restrictions may require using HTTPS or an appropriate
development network security configuration.

## Before real-user rollout

The current backend relies on caller-supplied numeric user IDs for GPS,
profile, opt-in settings, and WebSocket operations. There is no authenticated
authorization tying these IDs to the caller. **Do not expose this discovery
feature to real users or treat the opt-in as a security boundary** until
server-side authentication/authorization, abuse limits, and privacy review
are added. Test only with controlled accounts and consented test data.
