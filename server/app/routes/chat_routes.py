import json
import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db
from app.models.chat import ChatMessage
from app.models.room import ChatRoom
from app.models.user import User
from app.services.connection_manager import connection_manager

logger = logging.getLogger(__name__)
router = APIRouter()


class ChatHistoryRequest(BaseModel):
    roomId: str


def friend_room_id(user_id: int, friend_id: int) -> str:
    first, second = sorted((user_id, friend_id))
    return f'friend_{first}_{second}'


def ensure_friend_room(user_id: int, friend_id: int, db: Session) -> str:
    user = db.query(User).filter(User.id == user_id).first()
    friend = db.query(User).filter(User.id == friend_id).first()
    if user is None or friend is None:
        raise ValueError('User not found')

    if friend not in user.friends:
        user.friends.append(friend)
    if user not in friend.friends:
        friend.friends.append(user)

    room_id = friend_room_id(user_id, friend_id)
    if db.query(ChatRoom).filter(ChatRoom.id == room_id).first() is None:
        db.add(ChatRoom(id=room_id, name=f'Chat_{user_id}_{friend_id}'))
    db.commit()
    return room_id


def serialize_history(room_id: str, db: Session, limit: int = 50) -> list[dict]:
    messages = (
        db.query(ChatMessage)
        .filter(ChatMessage.room_id == room_id)
        .order_by(ChatMessage.timestamp.asc())
        .limit(limit)
        .all()
    )
    return [
        {
            'id': message.id,
            'type': 'text',
            'content': message.content,
            'sender': str(message.sender_id),
            'sender_id': message.sender_id,
            'timestamp': message.timestamp.isoformat(),
            'image_url': message.image_url,
        }
        for message in messages
    ]


@router.post('/chat_history')
def get_chat_history(payload: ChatHistoryRequest, db: Session = Depends(get_db)):
    if db.query(ChatRoom).filter(ChatRoom.id == payload.roomId).first() is None:
        raise HTTPException(status_code=404, detail='Chat room not found')
    return {'room_id': payload.roomId, 'messages': serialize_history(payload.roomId, db)}


async def _send_error(websocket: WebSocket, message: str) -> None:
    await websocket.send_text(json.dumps({'type': 'error', 'message': message}))


@router.websocket('/ws')
async def chat_gateway(websocket: WebSocket, db: Session = Depends(get_db)):
    await websocket.accept()
    current_user_id: str | None = None

    try:
        while True:
            try:
                data = json.loads(await websocket.receive_text())
            except json.JSONDecodeError:
                await _send_error(websocket, 'Invalid JSON format')
                continue

            message_type = data.get('type')

            if message_type == 'register_user':
                user_id = str(data.get('userId', ''))
                if not user_id.isdigit() or db.query(User).filter(User.id == int(user_id)).first() is None:
                    await _send_error(websocket, 'Invalid user ID. Please login first.')
                    continue
                current_user_id = user_id
                await connection_manager.connect_user(user_id, websocket, db)
                continue

            if current_user_id is None:
                await _send_error(websocket, 'Please register user first')
                continue

            if message_type == 'create_room':
                room_id = uuid.uuid4().hex[:8]
                db.add(ChatRoom(id=room_id, name=data.get('name')))
                db.commit()
                await connection_manager.send_to_user(
                    current_user_id,
                    {'type': 'room_created', 'roomId': room_id},
                )

            elif message_type == 'join_room':
                room_id = str(data.get('roomId', ''))
                if db.query(ChatRoom).filter(ChatRoom.id == room_id).first() is None:
                    await _send_error(websocket, 'Chat room not found')
                    continue
                await connection_manager.join_room(current_user_id, room_id)

            elif message_type == 'leave_room':
                room_id = str(data.get('roomId', ''))
                connection_manager.leave_room(current_user_id, room_id)
                await connection_manager.send_to_user(
                    current_user_id,
                    {'type': 'left_room', 'roomId': room_id},
                )

            elif message_type == 'message':
                room_id = str(data.get('roomId', ''))
                content = str(data.get('content', ''))
                if not room_id or not content:
                    await _send_error(websocket, 'roomId and content are required')
                    continue

                if db.query(ChatRoom).filter(ChatRoom.id == room_id).first() is None:
                    await _send_error(websocket, 'Chat room not found')
                    continue

                if connection_manager.user_rooms.get(current_user_id) != room_id:
                    await connection_manager.join_room(current_user_id, room_id)

                record = ChatMessage(
                    room_id=room_id,
                    sender_id=int(current_user_id),
                    content=content,
                    image_url=data.get('imageUrl'),
                )
                db.add(record)
                db.commit()
                db.refresh(record)

                response = {
                    'type': 'message',
                    'id': data.get('id') or str(record.id),
                    'roomId': room_id,
                    'sender': current_user_id,
                    'content': content,
                    'timestamp': data.get('timestamp') or record.timestamp.isoformat(),
                    'imageUrl': data.get('imageUrl'),
                }
                await connection_manager.broadcast_to_room(room_id, response)

            elif message_type == 'connect_request':
                from_user = str(data.get('from', ''))
                to_user = str(data.get('to', ''))
                if from_user != current_user_id:
                    await _send_error(websocket, 'from must match registered user')
                    continue

                if to_user == '0000':
                    await connection_manager.send_to_user(
                        from_user,
                        {
                            'type': 'connect_response',
                            'from': '0000',
                            'to': from_user,
                            'accept': True,
                        },
                    )
                else:
                    await connection_manager.send_to_user(
                        to_user,
                        {'type': 'connect_request', 'from': from_user, 'to': to_user},
                    )

            elif message_type == 'connect_response':
                from_user = str(data.get('from', ''))
                to_user = str(data.get('to', ''))
                accepted = bool(data.get('accept'))
                response = {
                    'type': 'connect_response',
                    'from': from_user,
                    'to': to_user,
                    'accept': accepted,
                }

                if accepted:
                    try:
                        room_id = ensure_friend_room(int(from_user), int(to_user), db)
                        response['roomId'] = room_id
                    except (ValueError, TypeError) as error:
                        response['error'] = str(error)

                await connection_manager.send_to_users([from_user, to_user], response)

            else:
                await _send_error(websocket, f'Unknown message type: {message_type}')

    except WebSocketDisconnect:
        if current_user_id is not None:
            await connection_manager.disconnect_user(current_user_id, db)
    except Exception:
        logger.exception('WebSocket gateway failed')
        if current_user_id is not None:
            await connection_manager.disconnect_user(current_user_id, db)
