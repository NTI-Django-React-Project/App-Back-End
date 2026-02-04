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
        DB_HOST = 'localhost'   // <-- fixed
        DB_PORT = '5432'

        IMAGE_TAG = "${BUILD_NUMBER}"
        PYTHONPATH = 'backend'    // ensures Django can find your project
    }

    options {
        timestamps()
        disableConcurrentBuilds()
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
                until docker exec ci-postgres pg_isready -U ${DB_USER}; do
                  sleep 2
                  echo "Postgres not ready yet..."
                done
                echo "Postgres is ready!"
                '''
            }
        }

        stage('Setup Python Environment') {
            steps {
                sh '''
                python3 -m venv venv
                . venv/bin/activate
                pip install --upgrade pip
                pip install -r backend/requirements.txt
                '''
            }
        }

        stage('Run Django Migrations') {
            steps {
                sh '''
                . venv/bin/activate
                export DB_HOST=${DB_HOST}
                export DB_NAME=${DB_NAME}
                export DB_USER=${DB_USER}
                export DB_PASSWORD=${DB_PASSWORD}
                export DB_PORT=${DB_PORT}

                cd backend
                python manage.py migrate --noinput
                '''
            }
        }

        stage('Run Tests + Coverage') {
            steps {
                sh '''
                . venv/bin/activate
                export DB_HOST=${DB_HOST}
                export DB_NAME=${DB_NAME}
                export DB_USER=${DB_USER}
                export DB_PASSWORD=${DB_PASSWORD}
                export DB_PORT=${DB_PORT}

                cd backend
                pytest --cov=. --cov-report=xml --cov-report=term
                '''
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
                      -Dsonar.exclusions=**/migrations/**,**/tests/**
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                cd backend
                docker build -t ${APP_NAME}:${IMAGE_TAG} .
                '''
            }
        }

        stage('Security Scan (Trivy)') {
            steps {
                sh '''
                trivy image --severity HIGH,CRITICAL ${APP_NAME}:${IMAGE_TAG}
                '''
            }
        }

        stage('Push Image to ECR') {
            steps {
                sh '''
                AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

                aws ecr get-login-password --region ${AWS_REGION} | \
                  docker login --username AWS --password-stdin \
                  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

                docker tag ${APP_NAME}:${IMAGE_TAG} \
                  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}

                docker push \
                  ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}:${IMAGE_TAG}
                '''
            }
        }
    }

    post {
        always {
            sh '''
            docker rm -f ci-postgres || true
            docker rmi ${APP_NAME}:${IMAGE_TAG} || true
            '''
            cleanWs()
        }

        success {
            echo "✅ CI pipeline completed successfully!"
        }

        failure {
            echo "❌ CI pipeline failed"
        }
    }
}

