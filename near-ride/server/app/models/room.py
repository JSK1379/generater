from sqlalchemy import Column, DateTime, String, func

from app.database import Base


class ChatRoom(Base):
    __tablename__ = 'chat_rooms'

    id = Column(String, primary_key=True, index=True)
    name = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
