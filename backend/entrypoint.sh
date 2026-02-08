#!/bin/sh
set -e

echo "Starting Django application..."

echo "Waiting for database connection..."

python << 'EOF'
import sys
import time
import psycopg2
from os import environ

max_retries = 30
retry_interval = 2

db_config = {
    "dbname": environ.get("DB_NAME", "postgres"),
    "user": environ.get("DB_USER", "postgres"),
    "password": environ.get("DB_PASSWORD", ""),
    "host": environ.get("DB_HOST", "localhost"),
    "port": environ.get("DB_PORT", "5432"),
}

for i in range(1, max_retries + 1):
    try:
        conn = psycopg2.connect(**db_config)
        conn.close()
        print("Database is ready!")
        sys.exit(0)
    except psycopg2.OperationalError:
        print(f"Database unavailable ({i}/{max_retries}) – retrying...")
        time.sleep(retry_interval)

print("ERROR: Could not connect to the database.")
sys.exit(1)
EOF

echo "Running database migrations..."
python manage.py migrate --noinput

echo "Collecting static files..."
python manage.py collectstatic --noinput || true

if [ -n "$DJANGO_SUPERUSER_USERNAME" ] && \
   [ -n "$DJANGO_SUPERUSER_PASSWORD" ] && \
   [ -n "$DJANGO_SUPERUSER_EMAIL" ]; then

  echo "Ensuring superuser exists..."
  python manage.py shell << EOF
from django.contrib.auth import get_user_model
User = get_user_model()

if not User.objects.filter(username="$DJANGO_SUPERUSER_USERNAME").exists():
    User.objects.create_superuser(
        "$DJANGO_SUPERUSER_USERNAME",
        "$DJANGO_SUPERUSER_EMAIL",
        "$DJANGO_SUPERUSER_PASSWORD"
    )
    print("Superuser created.")
else:
    print("Superuser already exists.")
EOF
fi

echo "Starting application server..."
exec "$@"

