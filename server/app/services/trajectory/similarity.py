"""Trajectory similarity algorithms with no database or visualization concerns."""

from __future__ import annotations

from difflib import SequenceMatcher
from math import asin, cos, exp, radians, sin, sqrt

import numpy as np
import pandas as pd

from .geohash import GeohashEncoder


def _haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius_m = 6_371_000.0
    p1, p2 = radians(lat1), radians(lat2)
    dphi = radians(lat2 - lat1)
    dlambda = radians(lon2 - lon1)
    a = sin(dphi / 2) ** 2 + cos(p1) * cos(p2) * sin(dlambda / 2) ** 2
    return 2 * radius_m * asin(sqrt(a))


def geohash_similarity(
    first: pd.DataFrame,
    second: pd.DataFrame,
    *,
    precision: int = 7,
) -> float:
    encoder = GeohashEncoder(precision)
    seq1 = encoder.encode_trajectory(first)
    seq2 = encoder.encode_trajectory(second)
    if not seq1 or not seq2:
        return 0.0
    return float(SequenceMatcher(None, seq1, seq2).ratio())


def distance_similarity(
    first: pd.DataFrame,
    second: pd.DataFrame,
    *,
    time_window_minutes: int = 30,
    distance_threshold_m: float = 100.0,
) -> float:
    """Return the fraction of first-route points matched by a nearby second-route point."""
    if first.empty or second.empty:
        return 0.0

    a = first.copy()
    b = second.copy()
    a["timestamp"] = pd.to_datetime(a["timestamp"], utc=True)
    b["timestamp"] = pd.to_datetime(b["timestamp"], utc=True)
    window_seconds = time_window_minutes * 60

    matches = 0
    for point in a.itertuples(index=False):
        delta = (b["timestamp"] - point.timestamp).abs().dt.total_seconds()
        candidates = b[delta <= window_seconds]
        if candidates.empty:
            continue

        nearest = min(
            _haversine_m(
                float(point.latitude),
                float(point.longitude),
                float(candidate.latitude),
                float(candidate.longitude),
            )
            for candidate in candidates.itertuples(index=False)
        )
        if nearest <= distance_threshold_m:
            matches += 1

    return matches / len(a)


def dtw_similarity(first: pd.DataFrame, second: pd.DataFrame, *, scale_m: float = 1000.0) -> float:
    """Dynamic-time-warping similarity normalized to 0..1."""
    if first.empty or second.empty:
        return 0.0

    a = first[["latitude", "longitude"]].to_numpy(dtype=float)
    b = second[["latitude", "longitude"]].to_numpy(dtype=float)
    matrix = np.full((len(a) + 1, len(b) + 1), np.inf)
    matrix[0, 0] = 0.0

    for i in range(1, len(a) + 1):
        for j in range(1, len(b) + 1):
            cost = _haversine_m(a[i - 1][0], a[i - 1][1], b[j - 1][0], b[j - 1][1])
            matrix[i, j] = cost + min(matrix[i - 1, j], matrix[i, j - 1], matrix[i - 1, j - 1])

    return float(exp(-matrix[len(a), len(b)] / max(scale_m, 1.0)))


def hybrid_similarity(first: pd.DataFrame, second: pd.DataFrame) -> float:
    """Default Near Ride score: fast spatial sequence + local distance + DTW."""
    return (
        0.4 * geohash_similarity(first, second)
        + 0.3 * distance_similarity(first, second)
        + 0.3 * dtw_similarity(first, second)
    )


def calculate_similarity(first: pd.DataFrame, second: pd.DataFrame, method: str = "hybrid") -> float:
    methods = {
        "geohash": geohash_similarity,
        "distance": distance_similarity,
        "dtw": dtw_similarity,
        "hybrid": hybrid_similarity,
    }
    try:
        calculator = methods[method]
    except KeyError as exc:
        raise ValueError(f"unknown similarity method: {method}") from exc
    return float(calculator(first, second))
