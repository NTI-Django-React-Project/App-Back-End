#!/bin/bash
set -e

echo "Starting Django application..."

# Wait for database to be ready
echo "Waiting for database connection..."
python << END
import sys
import time
import psycopg2
from os import environ

max_retries = 30
retry_interval = 2

for i in range(max_retries):
    try:
        conn = psycopg2.connect(
            dbname=environ.get('DB_NAME', 'postgres'),
            user=environ.get('DB_USER', 'postgres'),
            password=environ.get('DB_PASSWORD', ''),
            host=environ.get('DB_HOST', 'localhost'),
            port=environ.get('DB_PORT', '5432')
        )
        conn.close()
        print("Database is ready!")
        sys.exit(0)
    except psycopg2.OperationalError:
        print(f"Database unavailable, waiting... ({i+1}/{max_retries})")
        time.sleep(retry_interval)

print("Could not connect to database!")
sys.exit(1)
END

# Run database migrations
echo "Running database migrations..."
python manage.py migrate --noinput

# Collect static files
echo "Collecting static files..."
python manage.py collectstatic --noinput --clear

# Create superuser if it doesn't exist (optional, for development)
if [ "$DJANGO_SUPERUSER_USERNAME" ] && [ "$DJANGO_SUPERUSER_PASSWORD" ] && [ "$DJANGO_SUPERUSER_EMAIL" ]; then
    echo "Creating superuser..."
    python manage.py shell << END
from django.contrib.auth import get_user_model
User = get_user_model()
if not User.objects.filter(username='$DJANGO_SUPERUSER_USERNAME').exists():
    User.objects.create_superuser('$DJANGO_SUPERUSER_USERNAME', '$DJANGO_SUPERUSER_EMAIL', '$DJANGO_SUPERUSER_PASSWORD')
    print('Superuser created.')
else:
    print('Superuser already exists.')
END
fi

echo "Starting application server..."
exec "$@"
