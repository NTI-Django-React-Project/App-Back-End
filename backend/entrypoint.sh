#!/bin/sh
set -e

echo "Starting Django application..."
echo "Waiting for database connection..."

python << END
import time, psycopg2, os

for i in range(30):
    try:
        psycopg2.connect(
            dbname=os.getenv("DB_NAME"),
            user=os.getenv("DB_USERNAME"),
            password=os.getenv("DB_PASSWORD"),
            host=os.getenv("DB_HOST"),
            port=os.getenv("DB_PORT"),
        )
        print("Database is ready!")
        break
    except Exception as e:
        print(f"DB not ready ({i+1}/30):", e)
        time.sleep(2)
else:
    print("Database not reachable, exiting.")
    exit(1)
END

echo "Running migrations..."
python manage.py migrate --noinput

echo "Collecting static files..."
python manage.py collectstatic --noinput || true

exec "$@"

