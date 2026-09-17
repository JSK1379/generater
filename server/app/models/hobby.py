from sqlalchemy import Column, Integer, String
from sqlalchemy.orm import relationship

from app.database import Base
from app.models.user import user_hobbies


class Hobby(Base):
    __tablename__ = 'hobbies'

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True)
    description = Column(String, nullable=True)

    users = relationship('User', secondary=user_hobbies, back_populates='hobbies')
