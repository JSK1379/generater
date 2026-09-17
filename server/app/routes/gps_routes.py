from collections import defaultdict
from datetime import datetime, time, timedelta
from typing import Optional

import pandas as pd
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, field_validator
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.gps_route import GPSLocation
from app.models.user import User
from app.services.trajectory import TrajectoryAnalyzer

router = APIRouter()


class GPSLocationData(BaseModel):
    lat: float
    lng: float
    ts: str

    @field_validator('lat')
    @classmethod
    def validate_latitude(cls, value: float) -> float:
        if not -90 <= value <= 90:
            raise ValueError('緯度必須在 -90 到 90 之間')
        return value

    @field_validator('lng')
    @classmethod
    def validate_longitude(cls, value: float) -> float:
        if not -180 <= value <= 180:
            raise ValueError('經度必須在 -180 到 180 之間')
        return value


class GPSRouteUpload(BaseModel):
    user_id: int
    date: str | None = None
    route: list[GPSLocationData]


def _require_user(db: Session, user_id: int) -> User:
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail='用戶不存在')
    return user


def _parse_timestamp(value: str) -> datetime:
    try:
        return datetime.fromisoformat(value.replace('Z', '+00:00')).replace(tzinfo=None)
    except ValueError:
        raise HTTPException(status_code=400, detail='時間格式無效')


def _serialize(location: GPSLocation) -> dict:
    return {
        'id': location.id,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'timestamp': location.timestamp.isoformat(),
    }


@router.post('/gps/location')
def record_gps_location(
    payload: GPSLocationData,
    user_id: int,
    db: Session = Depends(get_db),
):
    _require_user(db, user_id)
    location = GPSLocation(
        user_id=user_id,
        latitude=payload.lat,
        longitude=payload.lng,
        timestamp=_parse_timestamp(payload.ts),
    )
    db.add(location)
    db.commit()
    db.refresh(location)
    return {'message': 'GPS 定位記錄成功', 'user_id': user_id, **_serialize(location)}


@router.post('/gps/upload')
def upload_gps_route(
    payload: GPSRouteUpload,
    db: Session = Depends(get_db),
):
    """Compatibility endpoint for the existing commute recorder.

    Route points are normalized into the same gps_locations table used by the
    new single-point endpoint, so there is only one source of GPS data.
    """
    _require_user(db, payload.user_id)
    if not payload.route:
        raise HTTPException(status_code=400, detail='路線不能為空')
    if len(payload.route) > 10000:
        raise HTTPException(status_code=400, detail='路線點數過多')

    rows = [
        GPSLocation(
            user_id=payload.user_id,
            latitude=point.lat,
            longitude=point.lng,
            timestamp=_parse_timestamp(point.ts),
        )
        for point in payload.route
    ]
    db.add_all(rows)
    db.commit()
    return {
        'message': 'GPS 路線上傳成功',
        'user_id': payload.user_id,
        'date': payload.date,
        'points_saved': len(rows),
    }


@router.get('/gps/locations/{user_id}')
def get_user_locations(
    user_id: int,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    limit: int = Query(1000, ge=1, le=10000),
    db: Session = Depends(get_db),
):
    _require_user(db, user_id)
    query = db.query(GPSLocation).filter(GPSLocation.user_id == user_id)

    try:
        if start_date:
            query = query.filter(GPSLocation.timestamp >= datetime.strptime(start_date, '%Y-%m-%d'))
        if end_date:
            end = datetime.combine(datetime.strptime(end_date, '%Y-%m-%d').date(), time.max)
            query = query.filter(GPSLocation.timestamp <= end)
    except ValueError:
        raise HTTPException(status_code=400, detail='日期格式無效，請使用 YYYY-MM-DD')

    locations = query.order_by(GPSLocation.timestamp.desc()).limit(limit).all()
    items = [_serialize(item) for item in locations]
    return {'user_id': user_id, 'total_locations': len(items), 'locations': items}


@router.get('/gps/locations/{user_id}/date/{date_text}')
def get_user_locations_by_date(
    user_id: int,
    date_text: str,
    db: Session = Depends(get_db),
):
    _require_user(db, user_id)
    try:
        target = datetime.strptime(date_text, '%Y-%m-%d').date()
    except ValueError:
        raise HTTPException(status_code=400, detail='日期格式無效，請使用 YYYY-MM-DD')

    start = datetime.combine(target, time.min)
    end = datetime.combine(target, time.max)
    locations = (
        db.query(GPSLocation)
        .filter(
            GPSLocation.user_id == user_id,
            GPSLocation.timestamp >= start,
            GPSLocation.timestamp <= end,
        )
        .order_by(GPSLocation.timestamp)
        .all()
    )
    items = [_serialize(item) for item in locations]
    return {
        'user_id': user_id,
        'date': date_text,
        'total_locations': len(items),
        'locations': items,
    }


@router.delete('/gps/locations/{user_id}')
def delete_user_locations(
    user_id: int,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    db: Session = Depends(get_db),
):
    _require_user(db, user_id)
    query = db.query(GPSLocation).filter(GPSLocation.user_id == user_id)
    try:
        if start_date:
            query = query.filter(GPSLocation.timestamp >= datetime.strptime(start_date, '%Y-%m-%d'))
        if end_date:
            end = datetime.combine(datetime.strptime(end_date, '%Y-%m-%d').date(), time.max)
            query = query.filter(GPSLocation.timestamp <= end)
    except ValueError:
        raise HTTPException(status_code=400, detail='日期格式無效，請使用 YYYY-MM-DD')

    count = query.count()
    query.delete(synchronize_session=False)
    db.commit()
    return {'message': 'GPS 定位記錄刪除成功', 'deleted_count': count}


@router.get('/gps/similar/{user_id}')
def find_similar_users(
    user_id: int,
    method: str = Query('hybrid', pattern='^(geohash|distance|dtw|hybrid)$'),
    threshold: float = Query(0.3, ge=0.0, le=1.0),
    days: int = Query(7, ge=1, le=90),
    max_results: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
):
    """Find users whose recent GPS trajectories are similar to the target user."""
    _require_user(db, user_id)
    cutoff = datetime.now() - timedelta(days=days)
    rows = (
        db.query(GPSLocation)
        .filter(GPSLocation.timestamp >= cutoff)
        .order_by(GPSLocation.user_id, GPSLocation.timestamp)
        .all()
    )

    grouped: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        grouped[str(row.user_id)].append(
            {
                'latitude': row.latitude,
                'longitude': row.longitude,
                'timestamp': row.timestamp,
            }
        )

    trajectories = {
        uid: pd.DataFrame(points)
        for uid, points in grouped.items()
        if points
    }
    target = str(user_id)
    if target not in trajectories:
        return {
            'user_id': user_id,
            'method': method,
            'threshold': threshold,
            'matches': [],
            'reason': 'target user has no GPS data in the selected window',
        }

    analyzer = TrajectoryAnalyzer(method=method, threshold=threshold)
    matches = analyzer.find_similar(target, trajectories, max_results=max_results)
    return {
        'user_id': user_id,
        'method': method,
        'threshold': threshold,
        'window_days': days,
        'matches': matches,
    }
