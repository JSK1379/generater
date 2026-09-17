import logging
from datetime import datetime
from typing import List, Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, EmailStr
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.hobby import Hobby
from app.models.user import User
from app.models.user_status import UserStatus
from app.services.avatar_service import cloud_avatar_service

logger = logging.getLogger(__name__)
router = APIRouter()


class UserCreate(BaseModel):
    email: EmailStr
    password: str


class UserLogin(BaseModel):
    email: EmailStr
    password: str


class UserUpdate(BaseModel):
    email: Optional[str] = None
    password: Optional[str] = None
    nickname: Optional[str] = None
    avatar_url: Optional[str] = None
    avatar_base64: Optional[str] = None
    gender: Optional[str] = None
    age: Optional[int] = None
    location: Optional[str] = None
    hobby_ids: Optional[List[int]] = None
    custom_hobby_description: Optional[str] = None


class AvatarUpload(BaseModel):
    avatar_base64: str


def _serialize_user(user: User) -> dict:
    return {
        'id': user.id,
        'email': user.email,
        'nickname': user.nickname,
        'avatar_url': user.avatar_url,
        'gender': user.gender,
        'age': user.age,
        'location': user.location,
        'custom_hobby_description': user.custom_hobby_description,
        'hobbies': [
            {
                'id': hobby.id,
                'name': hobby.name,
                'description': hobby.description,
            }
            for hobby in user.hobbies
        ],
    }


@router.post('/')
def create_user(payload: UserCreate, db: Session = Depends(get_db)):
    if db.query(User).filter(User.email == payload.email).first():
        raise HTTPException(status_code=400, detail='信箱重複')

    user = User(email=payload.email, password=payload.password)
    db.add(user)
    try:
        db.commit()
        db.refresh(user)
        db.add(UserStatus(user_id=user.id, status='offline'))
        db.commit()
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail='信箱重複')

    return {'id': str(user.id), 'userId': str(user.id), 'email': user.email}


@router.post('/login')
def login_user(payload: UserLogin, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email).first()
    if user is None:
        raise HTTPException(status_code=404, detail='此信箱尚未註冊')
    if user.password != payload.password:
        raise HTTPException(status_code=401, detail='密碼錯誤')

    status = db.query(UserStatus).filter(UserStatus.user_id == user.id).first()
    if status is None:
        status = UserStatus(user_id=user.id)
        db.add(status)
    status.status = 'online'
    status.connected_at = datetime.now()
    db.commit()

    serialized = _serialize_user(user)
    user_id = str(user.id)
    return {
        'id': user_id,
        'userId': user_id,
        'user_id': user_id,
        'message': '登入成功',
        'user': serialized,
        'login_time': datetime.now().isoformat(),
    }


@router.get('/{user_id}')
def get_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail='User not found')
    return _serialize_user(user)


@router.put('/{user_id}')
@router.patch('/{user_id}')
def update_user(
    user_id: int,
    payload: UserUpdate,
    request: Request,
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail='用戶不存在')

    if payload.email is not None:
        user.email = payload.email
    if payload.password is not None:
        user.password = payload.password
    if payload.nickname is not None:
        user.nickname = payload.nickname
    if payload.gender is not None:
        user.gender = payload.gender
    if payload.age is not None:
        user.age = payload.age
    if payload.location is not None:
        user.location = payload.location
    if payload.custom_hobby_description is not None:
        user.custom_hobby_description = payload.custom_hobby_description

    if payload.avatar_base64:
        if user.avatar_url:
            cloud_avatar_service.delete_avatar(user.avatar_url)
        user.avatar_url = cloud_avatar_service.save_avatar(
            payload.avatar_base64,
            user_id,
            str(request.url),
        )
    elif payload.avatar_url is not None:
        user.avatar_url = payload.avatar_url

    if payload.hobby_ids is not None:
        user.hobbies = db.query(Hobby).filter(Hobby.id.in_(payload.hobby_ids)).all()

    try:
        db.commit()
        db.refresh(user)
    except IntegrityError:
        db.rollback()
        raise HTTPException(status_code=400, detail='資料更新衝突')

    return {'message': '用戶資料更新成功', 'user': _serialize_user(user)}


@router.post('/{user_id}/avatar')
def upload_avatar(
    user_id: int,
    payload: AvatarUpload,
    request: Request,
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail='用戶不存在')

    if user.avatar_url:
        cloud_avatar_service.delete_avatar(user.avatar_url)
    user.avatar_url = cloud_avatar_service.save_avatar(
        payload.avatar_base64,
        user_id,
        str(request.url),
    )
    db.commit()
    return {'message': '頭像上傳成功', 'avatar_url': user.avatar_url, 'user_id': user_id}


@router.delete('/{user_id}/avatar')
def delete_avatar(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail='用戶不存在')
    if not user.avatar_url:
        raise HTTPException(status_code=404, detail='用戶沒有設定頭像')

    cloud_avatar_service.delete_avatar(user.avatar_url)
    user.avatar_url = None
    db.commit()
    return {'message': '頭像刪除成功', 'user_id': user_id}
