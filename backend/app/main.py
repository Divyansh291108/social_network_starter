from contextlib import asynccontextmanager
from fastapi import FastAPI
from app.database import Base, engine
from app import models  # Register model metadata
from app.routers import auth, posts, users
from fastapi.middleware.cors import CORSMiddleware
import os
from fastapi.staticfiles import StaticFiles
from app.storage import UPLOAD_DIR
from app.limiter import limiter

from app.routers import auth, posts, users
from app.config import settings


app = FastAPI(title="Social Network", version="0.1.0",  docs_url="/docs" if settings.enable_docs else None,
    redoc_url=None,
    openapi_url="/openapi.json" if settings.enable_docs else None,
) 

os.makedirs(UPLOAD_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=UPLOAD_DIR), name="uploads")


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Convenient for the first local prototype. Use Alembic migrations for real deployments.
    
    yield


#app = FastAPI(title="Social Network API", version="0.1.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
app.include_router(auth.router)
app.include_router(users.router)
app.include_router(posts.router)


@app.get("/")
def home():
    return {"message": "Social Network API", "docs": "/docs"}


@app.get("/health")
def health():
    return {"status": "ok"}
