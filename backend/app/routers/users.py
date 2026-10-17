import os

from fastapi import APIRouter, Depends, File, HTTPException, Request, UploadFile
from sqlalchemy import delete, func, or_, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.dependencies import get_current_user, get_optional_user
from app.limiter import limiter
from app.models import Block, Comment, Like, Post, Report, User
from app.schemas import DeleteAccountRequest, ProfilePublic, ProfileUpdate, UserPublic
from app.security import verify_password
from app.storage import looks_like_image, save_image

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/me", response_model=UserPublic)
def me(current_user: User = Depends(get_current_user)):
    return current_user


@router.patch("/me", response_model=UserPublic)
def update_me(
    payload: ProfileUpdate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    name = payload.display_name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="Display name cannot be empty.")
    current_user.display_name = name
    current_user.bio = payload.bio.strip()
    db.commit()
    db.refresh(current_user)
    return current_user


@router.post("/me/avatar")
@limiter.limit("10/minute")
async def upload_avatar(
    request: Request,
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in {".jpg", ".jpeg", ".png", ".webp"}:
        raise HTTPException(status_code=400, detail="Use a JPG, PNG or WEBP image.")
    data = await file.read()
    if len(data) > 2 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image must be under 2 MB.")
    if not looks_like_image(data):
        raise HTTPException(status_code=400, detail="That file is not a valid image.")
    current_user.avatar_url = await save_image(data, ext)
    db.commit()
    return {"avatar_url": current_user.avatar_url}


@router.post("/me/delete", status_code=204)
@limiter.limit("5/hour")
def delete_account(
    request: Request,
    payload: DeleteAccountRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    # Status 400 (not 401) on purpose: a wrong password must not look like an expired session.
    if not verify_password(payload.password, current_user.password_hash):
        raise HTTPException(status_code=400, detail="Incorrect password.")

    uid = current_user.id
    my_post_ids = select(Post.id).where(Post.author_id == uid)

    db.execute(delete(Like).where(or_(Like.user_id == uid, Like.post_id.in_(my_post_ids))))
    db.execute(delete(Comment).where(or_(Comment.author_id == uid, Comment.post_id.in_(my_post_ids))))
    db.execute(delete(Report).where(Report.reporter_id == uid))
    db.execute(delete(Block).where(or_(Block.blocker_id == uid, Block.blocked_id == uid)))
    db.execute(delete(Post).where(Post.author_id == uid))
    db.execute(delete(User).where(User.id == uid))
    db.commit()


@router.get("/{user_id}", response_model=ProfilePublic)
def get_profile(
    user_id: int,
    db: Session = Depends(get_db),
    me: User | None = Depends(get_optional_user),
):
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")

    post_count = db.scalar(
        select(func.count()).select_from(Post).where(Post.author_id == user_id)
    ) or 0
    is_blocked = bool(
        me
        and db.scalar(
            select(Block.id).where(Block.blocker_id == me.id, Block.blocked_id == user_id)
        )
    )

    out = ProfilePublic.model_validate(user)
    out.post_count = post_count
    out.is_blocked = is_blocked
    out.is_me = bool(me and me.id == user_id)
    return out


@router.post("/{user_id}/block", status_code=204)
@limiter.limit("30/hour")
def block_user(
    request: Request,
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="You cannot block yourself.")
    if db.get(User, user_id) is None:
        raise HTTPException(status_code=404, detail="User not found")
    exists = db.scalar(
        select(Block.id).where(Block.blocker_id == current_user.id, Block.blocked_id == user_id)
    )
    if not exists:
        db.add(Block(blocker_id=current_user.id, blocked_id=user_id))
        db.commit()


@router.delete("/{user_id}/block", status_code=204)
def unblock_user(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    db.execute(
        delete(Block).where(Block.blocker_id == current_user.id, Block.blocked_id == user_id)
    )
    db.commit()