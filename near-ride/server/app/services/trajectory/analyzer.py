"""High-level trajectory analysis API for Near Ride."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Mapping

import pandas as pd

from .similarity import calculate_similarity


@dataclass
class TrajectoryAnalyzer:
    """Compare one or many users' trajectories without owning database access."""

    method: str = "hybrid"
    threshold: float = 0.3

    def compare(self, first: pd.DataFrame, second: pd.DataFrame) -> float:
        return calculate_similarity(first, second, self.method)

    def find_similar(
        self,
        target_user_id: str,
        trajectories: Mapping[str, pd.DataFrame],
        *,
        max_results: int = 20,
    ) -> list[dict]:
        if target_user_id not in trajectories:
            raise KeyError(f"trajectory not found for user {target_user_id}")

        target = trajectories[target_user_id]
        matches: list[dict] = []
        for user_id, trajectory in trajectories.items():
            if user_id == target_user_id:
                continue
            score = self.compare(target, trajectory)
            if score >= self.threshold:
                matches.append({"user_id": user_id, "similarity": round(score, 6)})

        matches.sort(key=lambda item: item["similarity"], reverse=True)
        return matches[:max_results]

    def compare_all(self, trajectories: Mapping[str, pd.DataFrame]) -> pd.DataFrame:
        user_ids = list(trajectories)
        rows: list[dict] = []
        for index, first_id in enumerate(user_ids):
            for second_id in user_ids[index + 1 :]:
                rows.append(
                    {
                        "user1_id": first_id,
                        "user2_id": second_id,
                        "similarity_score": self.compare(
                            trajectories[first_id], trajectories[second_id]
                        ),
                    }
                )
        return pd.DataFrame(rows)
