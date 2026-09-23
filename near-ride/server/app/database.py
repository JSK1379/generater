import logging
import os

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

load_dotenv()
logger = logging.getLogger(__name__)

DATABASE_URL = os.getenv('DATABASE_URL', 'sqlite:///./near_ride.db')
_is_sqlite = DATABASE_URL.startswith('sqlite')

engine = create_engine(
    DATABASE_URL,
    connect_args={'check_same_thread': False} if _is_sqlite else {},
    pool_pre_ping=not _is_sqlite,
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def create_tables() -> None:
    # Import all models before create_all so relationships can be resolved.
    from app.models import chat, commute_route, gps_route, hobby, recommendation_preference, room, user, user_status  # noqa: F401

    Base.metadata.create_all(bind=engine)
    logger.info('Database tables are ready')


def initialize_hobbies() -> None:
    from app.models.hobby import Hobby

    default_hobbies = [
        ('閱讀', '喜歡透過書籍探索不同世界與觀點'),
        ('旅行', '熱愛探索新地方與文化'),
        ('烹飪', '享受親手製作美味料理的樂趣'),
        ('電影', '喜歡觀賞各類型影片並分享心得'),
        ('音樂', '喜愛聆聽或演奏音樂'),
        ('攝影', '用相機捕捉生活中的美好瞬間'),
        ('健身', '注重健康與身材管理'),
        ('瑜伽', '追求身心平衡與放鬆'),
        ('跑步', '喜歡挑戰自我、保持活力'),
        ('登山', '享受與大自然親近的時光'),
        ('游泳', '喜愛水中運動與放鬆'),
        ('跳舞', '以舞蹈表達情感與活力'),
        ('手作', '喜歡親手製作工藝或飾品'),
        ('繪畫', '用顏色與線條表達創意'),
        ('桌遊', '喜歡與朋友聚會玩遊戲'),
        ('電子遊戲', '享受虛擬世界的冒險'),
        ('咖啡', '喜歡品嚐與研究咖啡文化'),
        ('品酒', '欣賞紅酒、白酒或調酒的風味'),
        ('露營', '喜愛戶外生活與野營體驗'),
        ('衝浪', '追求海上刺激與自由感'),
        ('潛水', '探索海底世界與生態'),
        ('志工服務', '熱心參與公益與幫助他人'),
        ('寵物', '喜歡與動物相處'),
        ('園藝', '享受種植花草與照顧植物'),
        ('美食探索', '喜愛嘗試不同餐廳與料理'),
        ('語言學習', '對不同語言與文化有興趣'),
        ('攝影棚拍攝', '享受專業拍攝與造型'),
        ('汽車', '對車輛與駕駛有熱情'),
        ('天文', '喜歡觀星與宇宙探索'),
        ('模型製作', '熱愛製作與收藏模型'),
    ]

    db = SessionLocal()
    try:
        existing_names = {name for (name,) in db.query(Hobby.name).all()}
        for name, description in default_hobbies:
            if name not in existing_names:
                db.add(Hobby(name=name, description=description))
        db.commit()
    except Exception:
        db.rollback()
        logger.exception('Failed to initialize hobbies')
    finally:
        db.close()
