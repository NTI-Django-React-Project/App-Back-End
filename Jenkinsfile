stage('Debug Migration Issue') {
    steps {
        dir('backend') {
            sh '''
            . venv/bin/activate
            
            echo "=== Debugging migration issue ==="
            
            # Check what happens when creating test database
            python -c "
import os
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'gig_router.settings')
import django
django.setup()

from django.db import connection
from django.db.migrations.executor import MigrationExecutor

executor = MigrationExecutor(connection)
print('Migration loader issues:')
print('Applied migrations:', executor.loader.applied_migrations)
print('Disk migrations:', executor.loader.disk_migrations.keys())

# Try to create a test database manually
print('\\nTrying to create test database...')
from django.db.backends.base.creation import BaseDatabaseCreation
creation = BaseDatabaseCreation(connection)
try:
    test_db_name = creation._get_test_db_name()
    print(f'Test database name: {test_db_name}')
    creation._create_test_db(verbosity=1, autoclobber=True)
    print('Test database created successfully!')
except Exception as e:
    print(f'Error creating test database: {e}')
"
            '''
        }
    }
}
