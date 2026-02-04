pipeline {
    agent any

    environment {
        AWS_REGION = 'us-east-1'
        APP_NAME = 'django-backend'
        ECR_REPO = 'django-backend'
 	DB_ENGINE = 'django.db.backends.postgresql'
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
            steps { checkout scm }
        }

        stage('Start PostgreSQL') {
            steps {
                sh '''
                docker run -d --name ci-postgres \
                  -e POSTGRES_DB=${POSTGRES_DB} \
                  -e POSTGRES_USER=${POSTGRES_USER} \
                  -e POSTGRES_PASSWORD=${POSTGRES_PASSWORD} \
                  -p 5432:5432 postgres:15

                echo "Waiting for Postgres..."
                until docker exec ci-postgres pg_isready -U ${POSTGRES_USER}; do
                  sleep 2
                done
                '''
            }
        }

        stage('Setup Python') {
            steps {
                sh '''
                python3 -m venv venv
                . venv/bin/activate
                pip install -U pip
                pip install -r backend/requirements.txt
                '''
            }
        }

        stage('Run Migrations') {
            steps {
                sh '''
                . venv/bin/activate
                cd backend
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
                pytest --cov=. --cov-report=xml:coverage.xml --cov-report=term
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

        stage('Build Image') {
            steps {
                sh '''
                cd backend
                docker build -t ${APP_NAME}:${IMAGE_TAG} .
                '''
            }
        }

        stage('Security Scan') {
            steps {
                sh '''
                trivy image --severity HIGH,CRITICAL ${APP_NAME}:${IMAGE_TAG}
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
    }
}

