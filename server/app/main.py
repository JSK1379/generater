import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import create_tables, initialize_hobbies
from app.routes import (
    ai_routes,
    chat_routes,
    friend_routes,
    gps_routes,
    hobby_routes,
    image_routes,
    user_routes,
)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()],
)
logger = logging.getLogger(__name__)

@asynccontextmanager
async def lifespan(_: FastAPI):
    logger.info('Starting Near Ride Backend API')
    create_tables()
    initialize_hobbies()
    yield


app = FastAPI(
    title='Near Ride Backend API',
    version='1.1.0',
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)


app.include_router(user_routes.router, prefix='/users')
app.include_router(chat_routes.router)
app.include_router(friend_routes.router, prefix='/friends')
app.include_router(hobby_routes.router)
app.include_router(gps_routes.router)
app.include_router(ai_routes.router)
app.include_router(image_routes.router)


@app.get('/')
def read_root():
    return {'message': 'Near Ride API', 'status': 'running'}
