pipeline {
    agent any

    environment {
        AWS_REGION = 'us-east-1'
        APP_NAME = 'django-backend'
        ECR_REPO = 'backend-app'

        DB_ENGINE = 'django.db.backends.postgresql'
        DB_NAME = 'testdb'
        DB_USER = 'testuser'
        DB_PASSWORD = 'testpass'
        DB_HOST = 'localhost'
        DB_PORT = '5432'

        IMAGE_TAG = "${BUILD_NUMBER}"
        PYTHONPATH = 'backend'
        
        DJANGO_SETTINGS_MODULE = 'gig_router.settings'
        
        SECRET_KEY = 'django-insecure-test-key-for-ci'
        DEBUG = 'True'
        REDIS_URL = 'redis://localhost:6379/0'
        OPENAI_API_KEY = 'test-key'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 30, unit: 'MINUTES')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Start PostgreSQL for CI') {
            steps {
                sh '''
                docker rm -f ci-postgres || true

                docker run -d \
                  --name ci-postgres \
                  -e POSTGRES_DB=${DB_NAME} \
                  -e POSTGRES_USER=${DB_USER} \
                  -e POSTGRES_PASSWORD=${DB_PASSWORD} \
                  -p 5432:5432 \
                  postgres:15

                echo "Waiting for Postgres to be ready..."
                for i in {1..30}; do
                  if docker exec ci-postgres pg_isready -U ${DB_USER} 2>/dev/null; then
                    echo "PostgreSQL is ready!"
                    break
                  fi
                  echo "Waiting for PostgreSQL... (attempt $i/30)"
                  sleep 2
                done
                
                # Give PostgreSQL extra time to initialize
                sleep 5
                '''
            }
        }

        stage('Setup Python Environment') {
            steps {
                dir('backend') {
                    sh '''
                    python3 -m venv venv
                    . venv/bin/activate
                    pip install --upgrade pip setuptools wheel
                    pip install -r requirements.txt
                    
                    pip install pytest pytest-django pytest-cov pytest-xdist
                    pip install factory-boy Faker
                    '''
                }
            }
        }

        stage('Apply Migrations to Main Database') {
            steps {
                dir('backend') {
                    sh '''
                    . venv/bin/activate
                    
                    echo "=== Applying migrations to main database ==="
                    python manage.py migrate --noinput
                    
                    echo "=== Verifying migrations ==="
                    python manage.py showmigrations --list
                    '''
                }
            }
        }

        stage('Run Tests with Proper Database Setup') {
            steps {
                dir('backend') {
                    sh '''
                    . venv/bin/activate
                    
                    echo "=== Setting up test environment ==="
                    
                    # Method 1: Run Django's test command first to set up test database
                    echo "Running Django test command to set up test database..."
                    python manage.py test --noinput users.tests.UserModelTest.test_user_creation 2>&1 | head -50 || true
                    
                    echo "=== Running all tests with pytest ==="
                    # Now run all tests with pytest using the test database
                    pytest \
                        --ds=gig_router.settings \
                        --cov=. \
                        --cov-report=xml:coverage.xml \
                        --cov-report=html:htmlcov \
                        --cov-report=term \
                        --junitxml=junit-results.xml \
                        --disable-warnings \
                        --reuse-db \
                        -v \
                        --tb=short \
                        --create-db
                    '''
                }
            }
            post {
                always {
                    junit 'backend/junit-results.xml'
                    archiveArtifacts artifacts: 'backend/coverage.xml', fingerprint: true
                    
                    script {
                        if (fileExists('backend/htmlcov/index.html')) {
                            publishHTML(
                                target: [
                                    reportDir: 'backend/htmlcov',
                                    reportFiles: 'index.html',
                                    reportName: 'Coverage Report',
                                    alwaysLinkToLastBuild: true,
                                    keepAll: true,
                                    allowMissing: false
                                ]
                            )
                        }
                    }
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                dir('backend') {
                    withSonarQubeEnv('SonarQube') {
                        sh '''
                        sonar-scanner \
                          -Dsonar.projectKey=django-backend \
                          -Dsonar.sources=. \
                          -Dsonar.python.coverage.reportPaths=coverage.xml \
                          -Dsonar.exclusions=**/migrations/**,**/tests/** \
                          -Dsonar.tests=. \
                          -Dsonar.python.version=3.10
                        '''
                    }
                }
            }
        }

        stage('Build Docker Image') {
            when {
                expression { 
                    currentBuild.result == null || currentBuild.result == 'SUCCESS' 
                }
            }
            steps {
                dir('backend') {
                    sh '''
                    docker build -t ${APP_NAME}:${IMAGE_TAG} .
                    docker tag ${APP_NAME}:${IMAGE_TAG} ${APP_NAME}:latest
                    '''
                }
            }
        }

        stage('Security Scan (Trivy)') {
            when {
                expression { 
                    currentBuild.result == null || currentBuild.result == 'SUCCESS' 
                }
            }
            steps {
                sh '''
                trivy image --severity HIGH,CRITICAL --exit-code 0 --no-progress ${APP_NAME}:${IMAGE_TAG}
                '''
            }
        }
    }

    post {
        always {
            sh '''
            echo "Cleaning up Docker containers..."
            docker rm -f ci-postgres || true
            docker rmi ${APP_NAME}:${IMAGE_TAG} ${APP_NAME}:latest || true
            '''
            
            cleanWs(
                cleanWhenAborted: true,
                cleanWhenFailure: true,
                cleanWhenNotBuilt: true,
                cleanWhenSuccess: true,
                deleteDirs: true
            )
        }
        
        success {
            script {
                currentBuild.description = "✅ Build #${BUILD_NUMBER} Success"
            }
            echo "✅ CI pipeline completed successfully!"
        }
        
        failure {
            script {
                currentBuild.description = "❌ Build #${BUILD_NUMBER} Failed"
            }
            echo "❌ CI pipeline failed"
        }
    }
}
