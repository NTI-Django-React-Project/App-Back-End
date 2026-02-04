pipeline {
  agent any

  environment {
    PROJECT_NAME = 'gig-router-backend'
    BACKEND_DIR = 'backend'

    AWS_REGION = 'us-east-1'
    AWS_ACCOUNT_ID = '517757113300'
    ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    ECR_REPO = 'backend-app'

    SHORT_COMMIT = sh(returnStdout: true, script: "git rev-parse --short HEAD").trim()
    IMAGE_TAG = "${BUILD_NUMBER}-${SHORT_COMMIT}"

    DB_NAME = 'testdb'
    DB_USER = 'test'
    DB_PASS = 'test'
    DB_HOST = 'localhost'  // Use Docker container hostname
    DB_PORT = '5432'
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Start Postgres for CI') {
      steps {
        sh '''
        docker rm -f test-db || true

        docker run -d \
          --name test-db \
          -e POSTGRES_DB=${DB_NAME} \
          -e POSTGRES_USER=${DB_USER} \
          -e POSTGRES_PASSWORD=${DB_PASS} \
          -p 5432:5432 \
          postgres:15

        echo "Waiting for Postgres to be ready..."
        for i in {1..30}; do
          docker exec test-db pg_isready -U ${DB_USER} && break
          sleep 2
        done
        '''
      }
    }

    stage('Setup Python') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          python3 -m venv venv
          . venv/bin/activate
          pip install --upgrade pip
          pip install -r requirements.txt
          pip install pytest pytest-cov
          '''
        }
      }
    }

    stage('Migrate Database') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          . venv/bin/activate

          echo "Applying migrations to Postgres..."
          python manage.py migrate --noinput
          '''
        }
      }
    }

    stage('Run Migration Tests') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          . venv/bin/activate

          echo "Checking if migrations validated user-related tables..."
          python manage.py showmigrations
          python manage.py sqlmigrate users 0001  # Adjust to first migration

          echo "Checking database schema directly through database..."
          python manage.py dbshell << END
          SELECT * FROM information_schema.tables WHERE table_name = 'users_user';
          END
          '''
        }
      }
    }

    stage('Run Unit Tests') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          . venv/bin/activate

          echo "Running unit tests..."
          pytest --ds=gig_router.settings --cov=. --disable-warnings -m "unit"
          '''
        }
      }
    }

    stage('Run Integration Tests') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          . venv/bin/activate

          echo "Running integration tests..."
          pytest --ds=gig_router.settings --cov=. --disable-warnings -m "integration"
          '''
        }
      }
    }

    stage('Run All Tests') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          . venv/bin/activate

          echo "Running all tests..."
          pytest --ds=gig_router.settings --cov=. --cov-report=html
          '''
        }
      }
    }
  }

  post {
    always {
      sh 'docker rm -f test-db || true'
      cleanWs()
    }

    success {
      echo "✅ CI completed successfully!"
    }

    failure {
      echo "❌ CI failed. Fix tests and re-run."
    }
  }
}
