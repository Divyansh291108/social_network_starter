from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Block, User


def hidden_user_ids(db: Session, me: User | None) -> set[int]:
    """Users whose content `me` should not see: people I blocked and people who blocked me."""
    if me is None:
        return set()
    blocked_by_me = db.scalars(select(Block.blocked_id).where(Block.blocker_id == me.id)).all()
    blocking_me = db.scalars(select(Block.blocker_id).where(Block.blocked_id == me.id)).all()
    return set(blocked_by_me) | set(blocking_me)