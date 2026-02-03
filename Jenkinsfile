pipeline {
    agent any

    environment {
        AWS_REGION = 'us-east-1'
        APP_NAME = 'django-backend'
        ECR_REPO = 'django-backend'

        POSTGRES_DB = 'testdb'
        POSTGRES_USER = 'testuser'
        POSTGRES_PASSWORD = 'testpass'
        POSTGRES_HOST = 'localhost'
        POSTGRES_PORT = '5432'

        IMAGE_TAG = "${BUILD_NUMBER}"
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

        stage('Start PostgreSQL Container') {
            steps {
                sh '''
                docker run -d \
                  --name ci-postgres \
                  -e POSTGRES_DB=${POSTGRES_DB} \
                  -e POSTGRES_USER=${POSTGRES_USER} \
                  -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
                  -p 5432:5432 \
                  postgres:15

                echo "Waiting for Postgres..."
                sleep 15
                '''
            }
        }

        stage('Setup Python Env') {
            steps {
                sh '''
                python3 -m venv venv
                . venv/bin/activate
                pip install --upgrade pip
                pip install -r backend/requirements.txt
                '''
            }
        }

        stage('Run Migrations') {
            steps {
                sh '''
                . venv/bin/activate
                cd backend

                export DB_ENGINE=django.db.backends.postgresql
                export DB_NAME=${POSTGRES_DB}
                export DB_USER=${POSTGRES_USER}
                export DB_PASSWORD=${POSTGRES_PASSWORD}
                export DB_HOST=${POSTGRES_HOST}
                export DB_PORT=${POSTGRES_PORT}
                export SECRET_KEY=ci-secret
                export DEBUG=False

                python manage.py migrate
                '''
            }
        }

        stage('Run Tests') {
            steps {
                sh '''
                . venv/bin/activate
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

        stage('Trivy Scan') {
            steps {
                sh '''
                trivy image --severity HIGH,CRITICAL ${APP_NAME}:${IMAGE_TAG}
                '''
            }
        }

        stage('Push to ECR') {
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
            echo "✅ CI pipeline finished successfully!"
        }

        failure {
            echo "❌ CI pipeline failed"
        }
    }
}

