import json
import logging
import socket
from datetime import datetime
from typing import Dict, List, Optional

from fastapi import WebSocket
from sqlalchemy.orm import Session

from app.models.user_status import UserStatus

logger = logging.getLogger(__name__)


class ConnectionManager:
    def __init__(self) -> None:
        self.user_connections: Dict[str, WebSocket] = {}
        self.room_connections: Dict[str, List[WebSocket]] = {}
        self.user_rooms: Dict[str, str] = {}
        self.server_instance = socket.gethostname()

    async def connect_user(
        self,
        user_id: str,
        websocket: WebSocket,
        db: Optional[Session] = None,
    ) -> None:
        self.user_connections[user_id] = websocket
        if db is not None:
            await self._update_status(db, int(user_id), 'online')
        await self.send_to_user(user_id, {'type': 'user_registered', 'userId': user_id})

    async def disconnect_user(
        self,
        user_id: str,
        db: Optional[Session] = None,
    ) -> None:
        room_id = self.user_rooms.get(user_id)
        if room_id:
            self.leave_room(user_id, room_id)
        self.user_connections.pop(user_id, None)
        if db is not None:
            await self._update_status(db, int(user_id), 'offline')

    async def _update_status(self, db: Session, user_id: int, status: str) -> None:
        try:
            from app.models.user import User

            if db.query(User).filter(User.id == user_id).first() is None:
                return

            record = db.query(UserStatus).filter(UserStatus.user_id == user_id).first()
            if record is None:
                record = UserStatus(user_id=user_id)
                db.add(record)

            record.status = status
            record.server_instance = self.server_instance if status == 'online' else None
            record.connected_at = datetime.now() if status == 'online' else record.connected_at
            db.commit()
        except Exception:
            db.rollback()
            logger.exception('Failed to update user status for %s', user_id)

    async def join_room(self, user_id: str, room_id: str) -> bool:
        websocket = self.user_connections.get(user_id)
        if websocket is None or not room_id:
            return False

        old_room = self.user_rooms.get(user_id)
        if old_room and old_room != room_id:
            self.leave_room(user_id, old_room)

        room = self.room_connections.setdefault(room_id, [])
        if websocket not in room:
            room.append(websocket)
        self.user_rooms[user_id] = room_id
        await self.send_to_user(user_id, {'type': 'joined_room', 'roomId': room_id})
        return True

    def leave_room(self, user_id: str, room_id: str) -> None:
        websocket = self.user_connections.get(user_id)
        room = self.room_connections.get(room_id)
        if websocket is not None and room is not None and websocket in room:
            room.remove(websocket)
            if not room:
                self.room_connections.pop(room_id, None)
        self.user_rooms.pop(user_id, None)

    async def send_to_user(self, user_id: str, message: dict) -> bool:
        websocket = self.user_connections.get(str(user_id))
        if websocket is None:
            return False
        try:
            await websocket.send_text(json.dumps(message))
            return True
        except Exception:
            logger.exception('Failed to send websocket message to %s', user_id)
            await self.disconnect_user(str(user_id))
            return False

    async def send_to_users(self, user_ids: List[str], message: dict) -> List[bool]:
        return [await self.send_to_user(str(user_id), message) for user_id in user_ids]

    async def broadcast_to_room(self, room_id: str, message: dict) -> None:
        payload = json.dumps(message)
        room = list(self.room_connections.get(room_id, []))
        for websocket in room:
            try:
                await websocket.send_text(payload)
            except Exception:
                if websocket in self.room_connections.get(room_id, []):
                    self.room_connections[room_id].remove(websocket)

    def is_user_online(self, user_id: str) -> bool:
        return str(user_id) in self.user_connections

    def get_room_users(self, room_id: str) -> List[str]:
        return [user_id for user_id, joined in self.user_rooms.items() if joined == room_id]


connection_manager = ConnectionManager()
