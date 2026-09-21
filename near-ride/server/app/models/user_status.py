from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import relationship

from app.database import Base


class UserStatus(Base):
    __tablename__ = 'user_status'

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey('users.id'), unique=True, index=True)
    status = Column(String, default='offline')
    server_instance = Column(String, nullable=True)
    last_seen = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    connected_at = Column(DateTime(timezone=True), nullable=True)

    user = relationship('User', back_populates='status')
