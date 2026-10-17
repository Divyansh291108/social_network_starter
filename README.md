# Social Network Starter

Starter MVP: FastAPI + PostgreSQL + SQLAlchemy + JWT, plus a Flutter client starter.

## Backend setup (Windows PowerShell)

1. Install Python 3.11+ and PostgreSQL.
2. Create a database named `social_app` in PostgreSQL.
3. Copy `.env.example` to `.env` and update `DATABASE_URL` and `SECRET_KEY`.
4. From this folder:

```powershell
cd backend
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app.main:app --reload
```

Open http://127.0.0.1:8000/docs

## Flutter setup

Install Flutter SDK and Android Studio/Xcode as appropriate. From this folder:

```powershell
flutter create frontend
```

Replace `frontend/lib/main.dart` with `flutter_client/lib/main.dart`, then:

```powershell
cd frontend
flutter pub add http
flutter run -d chrome
```

For Android emulator, change the API base URL in `main.dart` to `http://10.0.2.2:8000`.
For a physical phone, use your computer's LAN IP and ensure both devices are on the same network.
For web, use `http://127.0.0.1:8000` locally.

## Included endpoints

- `GET /health`
- `POST /auth/register`
- `POST /auth/login`
- `GET /users/me` (Bearer token required)
- `GET /users/{user_id}`
- `POST /posts` (Bearer token required)
- `GET /posts`

Login accepts JSON: `{"email":"you@example.com","password":"your-password"}`.
The response contains an access token. Send it as `Authorization: Bearer <token>`.

## Important

This is a learning/MVP scaffold, not production-ready. Before public launch add Alembic migrations, email verification, password reset, rate limiting, robust token/session revocation, tests, media object storage, moderation/reporting, privacy enforcement, logging, and deployment secrets management. Do not commit `.env`.
