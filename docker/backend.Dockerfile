# ---- build: install python deps into a virtualenv ----
FROM python:3.12-alpine AS build
WORKDIR /app
RUN python -m venv /venv
COPY application/backend/requirements.txt .
RUN /venv/bin/pip install --no-cache-dir -r requirements.txt

# ---- runtime: no compiler, no pip cache, non-root ----
FROM python:3.12-alpine
RUN apk upgrade --no-cache && adduser -D -u 10001 app
WORKDIR /app
COPY --from=build /venv /venv
COPY application/backend/app ./app
COPY application/backend/alembic ./alembic
COPY application/backend/alembic.ini .
COPY --chmod=0755 docker/backend-entrypoint.sh /entrypoint.sh
ARG APP_VERSION=dev
ENV PATH="/venv/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 APP_VERSION=${APP_VERSION}
USER 10001
EXPOSE 8000
ENTRYPOINT ["/entrypoint.sh"]
