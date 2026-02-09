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
    "dbname": environ.get("DB_NAME", "gig-router"),
    "user": environ.get("DB_USER", "gig_router_user"),
    "password": environ.get("DB_PASSWORD", ""),
    "host": environ.get("DB_HOST", "localhost"),
    "port": environ.get("DB_PORT", "5432"),
    "sslmode": environ.get("DB_SSLMODE", "require"),
}

for i in range(1, max_retries + 1):
    try:
        conn = psycopg2.connect(**db_config)
        conn.close()
        print("Database is ready!")
        sys.exit(0)
    except psycopg2.OperationalError as e:
        print(f"Database unavailable ({i}/{max_retries}): {e}")
        time.sleep(retry_interval)

print("ERROR: Could not connect to the database.")
sys.exit(1)
EOF

echo "Running database migrations..."
python manage.py migrate --noinput

echo "Collecting static files..."
python manage.py collectstatic --noinput || true

echo "Starting application server..."
exec "$@"

