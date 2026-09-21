from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import relationship

from app.database import Base


class ChatMessage(Base):
    __tablename__ = 'chat_messages'

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    room_id = Column(String, index=True)
    sender_id = Column(Integer, ForeignKey('users.id'))
    content = Column(String)
    image_url = Column(String, nullable=True)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())

    sender = relationship('User')
