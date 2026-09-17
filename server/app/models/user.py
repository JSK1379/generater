from sqlalchemy import Column, ForeignKey, Integer, String, Table, Text
from sqlalchemy.orm import relationship

from app.database import Base

user_hobbies = Table(
    'user_hobbies',
    Base.metadata,
    Column('user_id', Integer, ForeignKey('users.id'), primary_key=True),
    Column('hobby_id', Integer, ForeignKey('hobbies.id'), primary_key=True),
)

user_friends = Table(
    'user_friends',
    Base.metadata,
    Column('user_id', Integer, ForeignKey('users.id'), primary_key=True),
    Column('friend_id', Integer, ForeignKey('users.id'), primary_key=True),
)


class User(Base):
    __tablename__ = 'users'

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    password = Column(String)
    nickname = Column(String, nullable=True)
    avatar_url = Column(String, nullable=True)
    gender = Column(String, nullable=True)
    age = Column(Integer, nullable=True)
    location = Column(String, nullable=True)
    custom_hobby_description = Column(Text, nullable=True)

    hobbies = relationship('Hobby', secondary=user_hobbies, back_populates='users')
    friends = relationship(
        'User',
        secondary=user_friends,
        primaryjoin=id == user_friends.c.user_id,
        secondaryjoin=id == user_friends.c.friend_id,
    )
    commute_routes = relationship('CommuteRoute', back_populates='user')
    status = relationship('UserStatus', back_populates='user')
    gps_locations = relationship('GPSLocation', back_populates='user')
