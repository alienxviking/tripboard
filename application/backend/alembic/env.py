from logging.config import fileConfig

from sqlalchemy import create_engine, text

from alembic import context
from app.config import settings
from app.db import Base
from app import models  # noqa: F401  (registers the tables on Base.metadata)

config = context.config
if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline():
    context.configure(url=settings.database_url, target_metadata=target_metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online():
    engine = create_engine(settings.database_url)
    with engine.connect() as connection:
        if connection.dialect.name == "postgresql":
            # several backend pods start at the same time - only one may run the migration
            connection.execute(text("SELECT pg_advisory_lock(424242)"))
            connection.commit()
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()
        if connection.dialect.name == "postgresql":
            connection.execute(text("SELECT pg_advisory_unlock(424242)"))
            connection.commit()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
