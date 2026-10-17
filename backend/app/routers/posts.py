import os

from fastapi import APIRouter, Depends, File, HTTPException, Query, Request, UploadFile
from sqlalchemy import select
from sqlalchemy.orm import Session, joinedload

from app.database import get_db
from app.dependencies import get_current_user, get_optional_user
from app.limiter import limiter
from app.Moderation import hidden_user_ids
from app.models import Comment, Like, Post, Report, User
from app.schemas import (
    CommentCreate,
    CommentPublic,
    PostCreate,
    PostPublic,
    ReportCreate,
)
from app.storage import looks_like_image, save_image

router = APIRouter(prefix="/posts", tags=["posts"])


def serialize_post(db: Session, post: Post, me: User | None = None) -> PostPublic:
    out = PostPublic.model_validate(post)
    out.like_count = db.query(Like).filter(Like.post_id == post.id).count()
    out.comment_count = db.query(Comment).filter(Comment.post_id == post.id).count()
    out.liked_by_me = bool(
        me and db.query(Like).filter_by(user_id=me.id, post_id=post.id).first()
    )
    return out


@router.post("", response_model=PostPublic, status_code=201)
@limiter.limit("20/minute")
def create_post(
    request: Request,
    payload: PostCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    post = Post(
        author_id=current_user.id,
        content=payload.content.strip(),
        image_url=payload.image_url,
    )
    db.add(post)
    db.commit()
    db.refresh(post)
    return serialize_post(db, post, current_user)


@router.get("", response_model=list[PostPublic])
def list_posts(
    offset: int = Query(default=0, ge=0),
    limit: int = Query(default=20, ge=1, le=100),
    user_id: int | None = Query(default=None),
    db: Session = Depends(get_db),
    me: User | None = Depends(get_optional_user),
):
    statement = (
        select(Post)
        .options(joinedload(Post.author))
        .order_by(Post.created_at.desc(), Post.id.desc())
    )
    if user_id is not None:
        statement = statement.where(Post.author_id == user_id)
    hidden = hidden_user_ids(db, me)
    if hidden:
        statement = statement.where(Post.author_id.not_in(list(hidden)))
    posts = db.scalars(statement.offset(offset).limit(limit)).all()
    return [serialize_post(db, p, me) for p in posts]


@router.post("/upload-image")
@limiter.limit("10/minute")
async def upload_post_image(
    request: Request,
    file: UploadFile = File(...),
    me: User = Depends(get_current_user),
):
    ext = os.path.splitext(file.filename or "")[1].lower()
    if ext not in {".jpg", ".jpeg", ".png", ".webp", ".gif"}:
        raise HTTPException(status_code=400, detail="Use a JPG, PNG, WEBP or GIF image.")
    data = await file.read()
    if len(data) > 5 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Image must be under 5 MB.")
    if not looks_like_image(data):
        raise HTTPException(status_code=400, detail="That file is not a valid image.")
    return {"image_url": await save_image(data, ext)}


@router.post("/{post_id}/like")
@limiter.limit("60/minute")
def toggle_like(
    request: Request,
    post_id: int,
    db: Session = Depends(get_db),
    me: User = Depends(get_current_user),
):
    if not db.get(Post, post_id):
        raise HTTPException(status_code=404, detail="Post not found.")
    like = db.query(Like).filter_by(user_id=me.id, post_id=post_id).first()
    if like:
        db.delete(like)
        liked = False
    else:
        db.add(Like(user_id=me.id, post_id=post_id))
        liked = True
    db.commit()
    count = db.query(Like).filter_by(post_id=post_id).count()
    return {"liked": liked, "like_count": count}


@router.post("/{post_id}/report", status_code=201)
@limiter.limit("10/hour")
def report_post(
    request: Request,
    post_id: int,
    body: ReportCreate,
    db: Session = Depends(get_db),
    me: User = Depends(get_current_user),
):
    if not db.get(Post, post_id):
        raise HTTPException(status_code=404, detail="Post not found.")
    db.add(
        Report(
            reporter_id=me.id,
            target_type="post",
            target_id=post_id,
            reason=body.reason.strip(),
        )
    )
    db.commit()
    return {"ok": True}


@router.get("/{post_id}/comments", response_model=list[CommentPublic])
def list_comments(
    post_id: int,
    db: Session = Depends(get_db),
    me: User | None = Depends(get_optional_user),
):
    statement = (
        select(Comment)
        .options(joinedload(Comment.author))
        .where(Comment.post_id == post_id)
        .order_by(Comment.created_at.asc())
    )
    hidden = hidden_user_ids(db, me)
    if hidden:
        statement = statement.where(Comment.author_id.not_in(list(hidden)))
    return db.scalars(statement).all()


@router.post("/{post_id}/comments", response_model=CommentPublic, status_code=201)
@limiter.limit("30/minute")
def add_comment(
    request: Request,
    post_id: int,
    body: CommentCreate,
    db: Session = Depends(get_db),
    me: User = Depends(get_current_user),
):
    if not db.get(Post, post_id):
        raise HTTPException(status_code=404, detail="Post not found.")
    comment = Comment(
        post_id=post_id,
        author_id=me.id,
        content=body.content.strip(),
        image_url=body.image_url,
    )
    db.add(comment)
    db.commit()
    db.refresh(comment)
    return comment


@router.post("/{post_id}/comments/{comment_id}/report", status_code=201)
@limiter.limit("10/hour")
def report_comment(
    request: Request,
    post_id: int,
    comment_id: int,
    body: ReportCreate,
    db: Session = Depends(get_db),
    me: User = Depends(get_current_user),
):
    comment = db.get(Comment, comment_id)
    if not comment or comment.post_id != post_id:
        raise HTTPException(status_code=404, detail="Comment not found.")
    db.add(
        Report(
            reporter_id=me.id,
            target_type="comment",
            target_id=comment_id,
            reason=body.reason.strip(),
        )
    )
    db.commit()
    return {"ok": True}


@router.delete("/{post_id}", status_code=204)
def delete_post(
    post_id: int,
    db: Session = Depends(get_db),
    me: User = Depends(get_current_user),
):
    post = db.get(Post, post_id)
    if not post:
        raise HTTPException(status_code=404, detail="Post not found.")
    if post.author_id != me.id:
        raise HTTPException(status_code=403, detail="You can only delete your own posts.")
    db.query(Like).filter(Like.post_id == post_id).delete()
    db.query(Comment).filter(Comment.post_id == post_id).delete()
    db.delete(post)
    db.commit()


@router.delete("/{post_id}/comments/{comment_id}", status_code=204)
def delete_comment(
    post_id: int,
    comment_id: int,
    db: Session = Depends(get_db),
    me: User = Depends(get_current_user),
):
    comment = db.get(Comment, comment_id)
    if not comment or comment.post_id != post_id:
        raise HTTPException(status_code=404, detail="Comment not found.")
    if comment.author_id != me.id:
        raise HTTPException(status_code=403, detail="You can only delete your own comments.")
    db.delete(comment)
    db.commit()