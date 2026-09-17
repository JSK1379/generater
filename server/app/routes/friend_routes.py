import logging

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.chat import ChatMessage
from app.models.room import ChatRoom
from app.models.user import User

logger = logging.getLogger(__name__)
router = APIRouter()


class FriendRequest(BaseModel):
    user_id: int
    friend_id: int


def generate_friend_room_id(user_id: int, friend_id: int) -> str:
    first, second = sorted((user_id, friend_id))
    return f'friend_{first}_{second}'


@router.post('/add_friend')
def add_friend(payload: FriendRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == payload.user_id).first()
    friend = db.query(User).filter(User.id == payload.friend_id).first()
    if user is None or friend is None:
        raise HTTPException(status_code=404, detail='User not found')

    if friend not in user.friends:
        user.friends.append(friend)
    if user not in friend.friends:
        friend.friends.append(user)

    room_id = generate_friend_room_id(payload.user_id, payload.friend_id)
    if db.query(ChatRoom).filter(ChatRoom.id == room_id).first() is None:
        db.add(ChatRoom(id=room_id, name=f'Chat_{payload.user_id}_{payload.friend_id}'))

    db.commit()
    return {
        'message': 'Friend added successfully',
        'room_id': room_id,
        'friend': {
            'id': friend.id,
            'email': friend.email,
            'nickname': friend.nickname,
        },
    }


@router.get('/friends/{user_id}')
def get_friends(user_id: int, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if user is None:
        raise HTTPException(status_code=404, detail='User not found')

    result = []
    for friend in user.friends:
        room_id = generate_friend_room_id(user_id, friend.id)
        last_message = (
            db.query(ChatMessage)
            .filter(ChatMessage.room_id == room_id)
            .order_by(ChatMessage.timestamp.desc())
            .first()
        )
        result.append(
            {
                'id': friend.id,
                'email': friend.email,
                'nickname': friend.nickname,
                'avatar_url': friend.avatar_url,
                'room_id': room_id,
                'last_message': (
                    {
                        'content': last_message.content,
                        'timestamp': last_message.timestamp.isoformat(),
                        'sender_id': last_message.sender_id,
                    }
                    if last_message
                    else None
                ),
            }
        )

    return {'friends': result, 'total': len(result)}


@router.delete('/remove_friend')
def remove_friend(payload: FriendRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == payload.user_id).first()
    friend = db.query(User).filter(User.id == payload.friend_id).first()
    if user is None or friend is None:
        raise HTTPException(status_code=404, detail='User not found')

    if friend in user.friends:
        user.friends.remove(friend)
    if user in friend.friends:
        friend.friends.remove(user)
    db.commit()
    return {'message': 'Friend removed successfully'}


@router.get('/chat_history/{room_id}')
def get_chat_history(
    room_id: str,
    limit: int = 50,
    offset: int = 0,
    db: Session = Depends(get_db),
):
    if db.query(ChatRoom).filter(ChatRoom.id == room_id).first() is None:
        raise HTTPException(status_code=404, detail='Chat room not found')

    messages = (
        db.query(ChatMessage)
        .filter(ChatMessage.room_id == room_id)
        .order_by(ChatMessage.timestamp.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )
    items = [
        {
            'id': message.id,
            'sender_id': message.sender_id,
            'content': message.content,
            'timestamp': message.timestamp.isoformat(),
            'image_url': message.image_url,
        }
        for message in reversed(messages)
    ]
    return {'room_id': room_id, 'messages': items, 'total': len(items)}
