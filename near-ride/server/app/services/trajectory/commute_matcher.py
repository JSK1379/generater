"""Estimate recurring route/time overlap from GPS points; timestamps are naive.

Records are not tagged as commutes. Recorded clock time may be inconsistent
across timezone conventions; this is an estimate, not proof of a shared trip.
"""
from math import ceil
import pandas as pd
from .similarity import _haversine_m

TIME_WINDOW_MINUTES = 30
NEARBY_METERS = 300.0


def same_route_and_time(first: pd.DataFrame, second: pd.DataFrame) -> bool:
    """Need >=2 nearby points observed at a similar time of day (dates may differ)."""
    if first.empty or second.empty:
        return False
    required = {'latitude', 'longitude', 'timestamp'}
    if not required.issubset(first.columns) or not required.issubset(second.columns):
        return False
    a = list(first.itertuples(index=False))
    b = list(second.itertuples(index=False))
    required_matches = max(2, ceil(min(len(a), len(b)) * 0.25))
    matched_first = 0
    matched_second: set[int] = set()

    for first_point in a:
        first_clock = first_point.timestamp.hour * 60 + first_point.timestamp.minute
        for second_index, second_point in enumerate(b):
            second_clock = second_point.timestamp.hour * 60 + second_point.timestamp.minute
            clock_delta = abs(first_clock - second_clock)
            if min(clock_delta, 1440 - clock_delta) > TIME_WINDOW_MINUTES:
                continue
            if _haversine_m(
                float(first_point.latitude),
                float(first_point.longitude),
                float(second_point.latitude),
                float(second_point.longitude),
            ) <= NEARBY_METERS:
                matched_first += 1
                matched_second.add(second_index)
                break
        if matched_first >= required_matches and len(matched_second) >= 2:
            return True
    return False


def recommendation_priority(shared_commute_mode: bool, route_and_time: bool) -> int:
    """Both conditions > same mode > same route/time > trajectory-only fallback."""
    return 2 * int(shared_commute_mode) + int(route_and_time)
