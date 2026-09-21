from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session

from app.database import get_db, initialize_hobbies
from app.models.hobby import Hobby

router = APIRouter()


class HobbyCreate(BaseModel):
    name: str
    description: str | None = None


@router.get('/health')
def health():
    return {'status': 'healthy'}


@router.get('/hobbies')
def get_hobbies(db: Session = Depends(get_db)):
    return [
        {'id': hobby.id, 'name': hobby.name, 'description': hobby.description}
        for hobby in db.query(Hobby).order_by(Hobby.id).all()
    ]


@router.post('/hobbies')
def create_hobby(payload: HobbyCreate, db: Session = Depends(get_db)):
    if db.query(Hobby).filter(Hobby.name == payload.name).first():
        raise HTTPException(status_code=400, detail='此興趣已存在')
    hobby = Hobby(name=payload.name, description=payload.description)
    db.add(hobby)
    db.commit()
    db.refresh(hobby)
    return {'id': hobby.id, 'name': hobby.name, 'description': hobby.description}


@router.post('/hobbies/initialize')
def initialize_default_hobbies():
    initialize_hobbies()
    return {'message': 'Hobbies initialized successfully'}
