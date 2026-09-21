"""Small geohash helpers used by the Near Ride trajectory service."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

import geohash2
import pandas as pd


@dataclass(frozen=True)
class GeohashEncoder:
    """Encode GPS points and trajectories at one configured precision."""

    precision: int = 7

    def __post_init__(self) -> None:
        if not 1 <= self.precision <= 12:
            raise ValueError("precision must be between 1 and 12")

    def encode_point(self, latitude: float, longitude: float) -> str:
        if not -90 <= latitude <= 90:
            raise ValueError("latitude must be between -90 and 90")
        if not -180 <= longitude <= 180:
            raise ValueError("longitude must be between -180 and 180")
        return geohash2.encode(latitude, longitude, self.precision)

    def encode_trajectory(self, trajectory: pd.DataFrame) -> list[str]:
        if trajectory.empty:
            return []

        required = {"latitude", "longitude"}
        if not required.issubset(trajectory.columns):
            raise ValueError("trajectory requires latitude and longitude columns")

        return [
            self.encode_point(float(row.latitude), float(row.longitude))
            for row in trajectory.itertuples(index=False)
        ]
