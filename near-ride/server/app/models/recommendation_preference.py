from sqlalchemy import Boolean, Column, ForeignKey, Integer

from app.database import Base


class RecommendationPreference(Base):
    """Opt-in setting for sharing a user's GPS similarity with friend discovery."""

    __tablename__ = 'recommendation_preferences'

    user_id = Column(Integer, ForeignKey('users.id'), primary_key=True)
    enabled = Column(Boolean, nullable=False, default=False)
