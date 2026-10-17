from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, sessionmaker
from app.config import settings


#engine = create_engine(settings.database_url, pool_pre_ping=True)

engine = create_engine(
    settings.database_url,
    pool_pre_ping=True,       # test a connection before using it
    pool_recycle=300,         # replace connections older than 5 minutes
    pool_size=5,
    max_overflow=5,
    connect_args={"connect_timeout": 15},   # allow time for Neon to wake up
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


