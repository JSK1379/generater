import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.database import create_tables, initialize_hobbies
from app.routes import chat_routes, friend_routes, gps_routes, hobby_routes, user_routes

# Import models so SQLAlchemy sees every table before create_all().
import app.models.chat  # noqa: F401,E402
import app.models.commute_route  # noqa: F401,E402
import app.models.hobby  # noqa: F401,E402
import app.models.user_status  # noqa: F401,E402

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[logging.StreamHandler()],
)
logger = logging.getLogger(__name__)

app = FastAPI(title='Near Ride Backend API', version='1.1.0')

app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)


@app.on_event('startup')
def startup() -> None:
    logger.info('Starting Near Ride Backend API')
    create_tables()
    initialize_hobbies()


app.include_router(user_routes.router, prefix='/users')
app.include_router(chat_routes.router)
app.include_router(friend_routes.router, prefix='/friends')
app.include_router(hobby_routes.router)
app.include_router(gps_routes.router)


@app.get('/')
def read_root():
    return {'message': 'Near Ride API', 'status': 'running'}
