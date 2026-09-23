"""Run from near-ride/server: python -m unittest discover -s tests -v."""

import unittest
from datetime import datetime

import pandas as pd
from pydantic import ValidationError

from app.routes.user_routes import UserUpdate
from app.services.trajectory.commute_matcher import (
    recommendation_priority,
    same_route_and_time,
)


class CommuteMatchingTests(unittest.TestCase):
    def track(self, day, hour=8):
        return pd.DataFrame([
            {'latitude': 25.000 + index * 0.001,
             'longitude': 121.000 + index * 0.001,
             'timestamp': datetime(2026, 9, day, hour, index * 3)}
            for index in range(8)
        ])

    def test_same_route_and_daily_time_on_different_dates(self):
        self.assertTrue(same_route_and_time(self.track(1), self.track(2)))
        self.assertFalse(same_route_and_time(self.track(1), self.track(2, 15)))

    def test_different_route_at_same_time_does_not_match(self):
        other = self.track(2)
        other['latitude'] += 1.0
        self.assertFalse(same_route_and_time(self.track(1), other))

    def test_shared_mode_and_time_have_first_priority(self):
        self.assertEqual(
            [recommendation_priority(mode, overlap)
             for mode, overlap in [(True, True), (True, False), (False, True), (False, False)]],
            [3, 2, 1, 0],
        )
        self.assertGreater((recommendation_priority(True, True), 0.3),
                           (recommendation_priority(False, True), 0.99))

    def test_commute_selection_validated_and_deduplicated(self):
        self.assertEqual(UserUpdate(commute_modes=['捷運', '捷運', '公車']).commute_modes,
                         ['捷運', '公車'])
        self.assertEqual(UserUpdate(commute_modes=[]).commute_modes, [])
        with self.assertRaises(ValidationError):
            UserUpdate(commute_modes=['飛機'])


if __name__ == '__main__':
    unittest.main()
