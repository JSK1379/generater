from sqlalchemy import Column, DateTime, Float, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import relationship

from app.database import Base


class CommuteRoute(Base):
    __tablename__ = 'commute_routes'

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey('users.id'))
    route_name = Column(String, nullable=True)
    start_latitude = Column(Float)
    start_longitude = Column(Float)
    start_address = Column(Text, nullable=True)
    end_latitude = Column(Float)
    end_longitude = Column(Float)
    end_address = Column(Text, nullable=True)
    gps_points = Column(Text, nullable=True)
    travel_time = Column(Integer, nullable=True)
    distance = Column(Float, nullable=True)
    transport_mode = Column(String, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    is_active = Column(String, default='active')

    user = relationship('User', back_populates='commute_routes')
