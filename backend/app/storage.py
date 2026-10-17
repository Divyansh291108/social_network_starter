import os
import uuid
from pathlib import Path

import cloudinary
import cloudinary.uploader
from starlette.concurrency import run_in_threadpool

from app.config import settings

#UPLOAD_DIR = "uploads"
#os.makedirs(UPLOAD_DIR, exist_ok=True)
UPLOAD_DIR = Path(__file__).resolve().parent.parent / "uploads"
UPLOAD_DIR.mkdir(exist_ok=True)

if settings.cloudinary_cloud_name:
    cloudinary.config(
        cloud_name=settings.cloudinary_cloud_name,
        api_key=settings.cloudinary_api_key,
        api_secret=settings.cloudinary_api_secret,
        secure=True,
    )


def _upload_cloudinary(data: bytes) -> str:
    result = cloudinary.uploader.upload(data, folder="social", resource_type="image")
    return result["secure_url"]


'''def _save_local(data: bytes, ext: str) -> str:
    name = f"{uuid.uuid4().hex}{ext}"
    with open(os.path.join(UPLOAD_DIR, name), "wb") as f:
        f.write(data)
    return f"/uploads/{name}"'''
def _save_local(data: bytes, ext: str) -> str:
    name = f"{uuid.uuid4().hex}{ext}"
    (UPLOAD_DIR / name).write_bytes(data)
    return f"/uploads/{name}"


async def save_image(data: bytes, ext: str) -> str:
    if settings.cloudinary_cloud_name:
        return await run_in_threadpool(_upload_cloudinary, data)
    return _save_local(data, ext)

def looks_like_image(d: bytes) -> bool:
    return (
        d.startswith(b"\xff\xd8\xff")
        or d.startswith(b"\x89PNG\r\n\x1a\n")
        or d.startswith(b"GIF8")
        or (d[:4] == b"RIFF" and d[8:12] == b"WEBP")
    )