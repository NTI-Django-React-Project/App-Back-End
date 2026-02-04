pipeline {
    agent any

    environment {
        AWS_REGION = 'us-east-1'
        APP_NAME = 'django-backend'
        ECR_REPO = 'django-backend'

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
                # Wait for PostgreSQL to start accepting connections
                for i in {1..30}; do
                  if docker exec ci-postgres pg_isready -U ${DB_USER} 2>/dev/null; then
                    echo "PostgreSQL is ready!"
                    break
                  fi
                  echo "Waiting for PostgreSQL... (attempt $i/30)"
                  sleep 2
                done
                
                # Additional wait to ensure PostgreSQL is fully initialized
                sleep 3
                '''
            }
        }

        stage('Setup Python Environment') {
            steps {
                sh '''
                cd backend
                python3 -m venv venv
                . venv/bin/activate
                pip install --upgrade pip setuptools wheel
                pip install -r requirements.txt
                
                # Install pytest and related packages
                pip install pytest pytest-django pytest-cov pytest-xdist
                pip install factory-boy Faker  # For test data generation
                '''
            }
        }

        stage('Run Django Migrations') {
            steps {
                sh '''
                . venv/bin/activate
                cd backend

                echo "Creating migrations..."
                python manage.py makemigrations --noinput || echo "No new migrations to create"

                echo "Applying migrations..."
                # Apply all migrations
                python manage.py migrate --noinput
                
                echo "Checking applied migrations..."
                python manage.py showmigrations
                '''
            }
        }

        stage('Collect Static Files') {
            steps {
                sh '''
                . venv/bin/activate
                cd backend
                python manage.py collectstatic --noinput
                '''
            }
        }

        stage('Run Tests with Pytest') {
            steps {
                sh '''
                . venv/bin/activate
                cd backend

                # Set Django settings module for pytest
                export DJANGO_SETTINGS_MODULE=gig_router.settings
                
                # Run tests with coverage
                pytest \
                    --ds=gig_router.settings \
                    --cov=. \
                    --cov-report=xml:coverage.xml \
                    --cov-report=html:htmlcov \
                    --cov-report=term \
                    --junitxml=junit-results.xml \
                    --disable-warnings \
                    -v \
                    --tb=short
                '''
            }
            post {
                always {
                    // Archive test results
                    junit 'backend/junit-results.xml'
                    
                    // Archive coverage report
                    publishHTML([
                        reportDir: 'backend/htmlcov',
                        reportFiles: 'index.html',
                        reportName: 'Coverage Report',
                        keepAll: true
                    ])
                }
            }
        }

        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('SonarQube') {
                    sh '''
                    cd backend
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

        stage('Quality Gate') {
            steps {
                timeout(time: 1, unit: 'HOURS') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                cd backend
                docker build -t ${APP_NAME}:${IMAGE_TAG} .
                docker tag ${APP_NAME}:${IMAGE_TAG} ${APP_NAME}:latest
                '''
            }
        }

        stage('Security Scan (Trivy)') {
            steps {
                sh '''
                # Scan the Docker image for vulnerabilities
                trivy image --severity HIGH,CRITICAL --exit-code 0 ${APP_NAME}:${IMAGE_TAG}
                '''
            }
        }

        stage('Push Image to ECR') {
            when {
                branch 'main'
            }
            steps {
                withCredentials([
                    awsCredentials(
                        credentialsId: 'aws-credentials',
                        accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                        secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

                    aws ecr get-login-password --region ${AWS_REGION} | \
                      docker login --username AWS --password-stdin \
                      ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

                    # Create repository if it doesn't exist
                    aws ecr describe-repositories --repository-names ${ECR_REPO} || \
                      aws ecr create-repository --repository-name ${ECR_REPO}

                    docker tag ${APP_NAME}:${IMAGE_TAG} \
                      ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}
                    
                    docker tag ${APP_NAME}:${IMAGE_TAG} \
                      ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest

                    docker push \
                      ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}
                    
                    docker push \
                      ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:latest
                    '''
                }
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
            echo "✅ CI pipeline completed successfully!"
            // Optional: Send success notification
        }
        
        failure {
            echo "❌ CI pipeline failed"
            // Optional: Send failure notification
            emailext(
                subject: "FAILED: Job '${env.JOB_NAME}' (${env.BUILD_NUMBER})",
                body: """Check console output at ${env.BUILD_URL}""",
                to: 'devops@example.com',
                attachLog: true
            )
        }
        
        unstable {
            echo "⚠️  Pipeline is unstable (tests failed)"
        }
    }
}
