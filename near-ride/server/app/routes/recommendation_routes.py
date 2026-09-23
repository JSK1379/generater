"""One-at-a-time, opt-in friend discovery based on recent GPS tracks.

No raw coordinates, trajectory points, email or precise home/work locations are
included in the response. Current location records are not yet commute-tagged.
"""

from datetime import datetime, timedelta

import pandas as pd
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.gps_route import GPSLocation
from app.models.recommendation_preference import RecommendationPreference
from app.models.user import User
from app.services.trajectory import TrajectoryAnalyzer
from app.services.trajectory.commute_matcher import recommendation_priority, same_route_and_time

router = APIRouter()
WINDOW_DAYS = 14
MIN_POINTS = 8
MAX_POINTS_PER_USER = 120
MAX_CANDIDATES = 50
MIN_SIMILARITY = 0.25


class RecommendationSetting(BaseModel):
    enabled: bool


def _require_user(db: Session, user_id: int) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail='用戶不存在')
    return user


def _recent_trajectory(db: Session, user_id: int, cutoff: datetime) -> pd.DataFrame:
    points = (
        db.query(GPSLocation)
        .filter(GPSLocation.user_id == user_id, GPSLocation.timestamp >= cutoff)
        .order_by(GPSLocation.timestamp.desc())
        .limit(MAX_POINTS_PER_USER)
        .all()
    )
    return pd.DataFrame([
        {'latitude': point.latitude, 'longitude': point.longitude, 'timestamp': point.timestamp}
        for point in reversed(points)
    ])


@router.get('/recommendation-settings/{user_id}')
def get_recommendation_settings(user_id: int, db: Session = Depends(get_db)):
    _require_user(db, user_id)
    setting = db.get(RecommendationPreference, user_id)
    return {'user_id': user_id, 'enabled': bool(setting and setting.enabled)}


@router.put('/recommendation-settings/{user_id}')
def set_recommendation_settings(
    user_id: int,
    payload: RecommendationSetting,
    db: Session = Depends(get_db),
):
    _require_user(db, user_id)
    setting = db.get(RecommendationPreference, user_id)
    if setting is None:
        setting = RecommendationPreference(user_id=user_id, enabled=payload.enabled)
        db.add(setting)
    else:
        setting.enabled = payload.enabled
    db.commit()
    return {'user_id': user_id, 'enabled': payload.enabled}


@router.get('/recommendation/{user_id}')
def get_recommendation(
    user_id: int,
    exclude_user_ids: list[int] | None = Query(default=None),
    db: Session = Depends(get_db),
):
    user = _require_user(db, user_id)
    setting = db.get(RecommendationPreference, user_id)
    if setting is None or not setting.enabled:
        return {'recommendation': None, 'reason': 'disabled'}

    cutoff = datetime.now() - timedelta(days=WINDOW_DAYS)
    target = _recent_trajectory(db, user_id, cutoff)
    if len(target) < MIN_POINTS:
        return {'recommendation': None, 'reason': 'insufficient_gps'}

    excluded = {user_id, *(friend.id for friend in user.friends)}
    excluded.update((exclude_user_ids or [])[:30])

    candidates = (
        db.query(User)
        .join(RecommendationPreference, RecommendationPreference.user_id == User.id)
        .filter(
            RecommendationPreference.enabled.is_(True),
            User.id.notin_(excluded),
        )
        .order_by(User.id)
        .limit(MAX_CANDIDATES)
        .all()
    )

    analyzer = TrajectoryAnalyzer(method='hybrid', threshold=MIN_SIMILARITY)
    requested_modes = {row.mode for row in user.commute_modes}
    best_user: User | None = None
    best_rank: tuple[int, float] | None = None
    best_shared_modes: set[str] = set()
    best_time_overlap = False

    for candidate in candidates:
        trajectory = _recent_trajectory(db, candidate.id, cutoff)
        if len(trajectory) < MIN_POINTS:
            continue
        score = analyzer.compare(target, trajectory)
        if score < MIN_SIMILARITY:
            continue
        shared_modes = requested_modes.intersection(row.mode for row in candidate.commute_modes)
        time_overlap = same_route_and_time(target, trajectory)
        rank = (recommendation_priority(bool(shared_modes), time_overlap), score)
        if best_rank is None or rank > best_rank:
            best_user, best_rank = candidate, rank
            best_shared_modes = shared_modes
            best_time_overlap = time_overlap

    if best_user is None:
        return {'recommendation': None, 'reason': 'no_match'}

    if best_shared_modes and best_time_overlap:
        match_reason = '通勤方式相同，近期 GPS 路線與每日時間帶相近'
    elif best_shared_modes:
        match_reason = '通勤方式相同，近期 GPS 路線相近'
    elif best_time_overlap:
        match_reason = '近期 GPS 路線與每日時間帶相近'
    else:
        match_reason = '近期 GPS 路線相近'

    return {
        'recommendation': {
            'user_id': str(best_user.id),
            'nickname': best_user.nickname or f'使用者 {best_user.id}',
            'avatar_url': best_user.avatar_url,
            'age': best_user.age,
            'gender': best_user.gender,
            'hobbies': [
                {'id': hobby.id, 'name': hobby.name}
                for hobby in best_user.hobbies
            ],
            'commute_modes': [row.mode for row in best_user.commute_modes],
            'shared_commute_modes': sorted(best_shared_modes),
            'match_reason': match_reason,
        },
        'reason': None,
    }
