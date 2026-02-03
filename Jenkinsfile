pipeline {
    agent any
    
    environment {
        AWS_REGION = 'us-east-1'
        ECR_REGISTRY = credentials('backend-ecr-registry')
        IMAGE_NAME = 'backend-app'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        
        // RDS Configuration
        RDS_DB_NAME = 'database-1'
        RDS_PORT = '5432'
        RDS_USERNAME = 'postgres'  // ← CHANGED from 'admin' to 'postgres'
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo '=== Checking out code from GitHub ==='
                checkout scm
            }
        }
        
        stage('Build') {
            steps {
                echo '=== Installing Python dependencies ==='
                dir('backend') {
                    sh '''
                        python3 --version
                        python3 -m venv venv
                        . venv/bin/activate
                        pip install --upgrade pip
                        pip install -r requirements.txt
                    '''
                }
            }
        }
        
        stage('Setup Test Database') {
            steps {
                echo '=== Setting up test database in RDS ==='
                dir('backend') {
                    withCredentials([
                        string(credentialsId: 'rds-host', variable: 'RDS_HOST'),
                        string(credentialsId: 'rds-password', variable: 'RDS_PASSWORD')
                    ]) {
                        sh '''
                            export PGPASSWORD="${RDS_PASSWORD}"
                            
                            # Create database if not exists
                            psql -h ${RDS_HOST} -U ${RDS_USERNAME} -d postgres \
                                -c "SELECT 1 FROM pg_database WHERE datname = '${RDS_DB_NAME}'" | grep -q 1 || \
                            psql -h ${RDS_HOST} -U ${RDS_USERNAME} -d postgres \
                                -c "CREATE DATABASE ${RDS_DB_NAME};"
                            
                            echo "✅ Test database ready"
                        '''
                    }
                }
            }
        }
        
        stage('Run Migrations') {
            steps {
                echo '=== Running database migrations ==='
                dir('backend') {
                    withCredentials([
                        string(credentialsId: 'rds-host', variable: 'RDS_HOST'),
                        string(credentialsId: 'rds-password', variable: 'RDS_PASSWORD')
                    ]) {
                        sh '''
                            . venv/bin/activate
                            
                            export DJANGO_SETTINGS_MODULE=gig_router.settings
                            export SECRET_KEY=test-secret-key-for-ci
                            export DEBUG=False
                            export ALLOWED_HOSTS=localhost
                            
                            export DB_ENGINE=django.db.backends.postgresql
                            export DB_NAME=${RDS_DB_NAME}
                            export DB_USER=${RDS_USERNAME}
                            export DB_PASSWORD=${RDS_PASSWORD}
                            export DB_HOST=${RDS_HOST}
                            export DB_PORT=${RDS_PORT}
                            
                            python manage.py migrate --noinput
                            echo "✅ Migrations completed"
                        '''
                    }
                }
            }
        }
        
        stage('Test') {
            steps {
                echo '=== Running Tests ==='
                dir('backend') {
                    withCredentials([
                        string(credentialsId: 'rds-host', variable: 'RDS_HOST'),
                        string(credentialsId: 'rds-password', variable: 'RDS_PASSWORD')
                    ]) {
                        sh '''
                            . venv/bin/activate
                            
                            export DJANGO_SETTINGS_MODULE=gig_router.settings
                            export SECRET_KEY=test-secret-key-for-ci
                            export DEBUG=False
                            export ALLOWED_HOSTS=localhost
                            
                            export DB_ENGINE=django.db.backends.postgresql
                            export DB_NAME=${RDS_DB_NAME}
                            export DB_USER=${RDS_USERNAME}
                            export DB_PASSWORD=${RDS_PASSWORD}
                            export DB_HOST=${RDS_HOST}
                            export DB_PORT=${RDS_PORT}
                            
                            export REDIS_URL=redis://localhost:6379/0
                            export OPENAI_API_KEY=test-key
                            
                            pytest -v --junitxml=test-results/pytest-report.xml \
                                   --cov=. --cov-report=xml --cov-report=html
                        '''
                    }
                }
            }
            post {
                always {
                    junit 'backend/test-results/pytest-report.xml'
                    publishHTML([
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'backend/htmlcov',
                        reportFiles: 'index.html',
                        reportName: 'Coverage Report'
                    ])
                }
            }
        }
        
        stage('Cleanup Test Data') {
            steps {
                echo '=== Cleaning up test data ==='
                dir('backend') {
                    withCredentials([
                        string(credentialsId: 'rds-host', variable: 'RDS_HOST'),
                        string(credentialsId: 'rds-password', variable: 'RDS_PASSWORD')
                    ]) {
                        sh '''
                            . venv/bin/activate
                            
                            export DJANGO_SETTINGS_MODULE=gig_router.settings
                            export SECRET_KEY=test-secret-key-for-ci
                            export DB_ENGINE=django.db.backends.postgresql
                            export DB_NAME=${RDS_DB_NAME}
                            export DB_USER=${RDS_USERNAME}
                            export DB_PASSWORD=${RDS_PASSWORD}
                            export DB_HOST=${RDS_HOST}
                            export DB_PORT=${RDS_PORT}
                            
                            python manage.py flush --noinput
                            echo "✅ Test data cleaned"
                        '''
                    }
                }
            }
        }
        
        // ... (rest of your stages: SonarQube, OWASP, Build, Trivy)
        
        stage('Push to ECR') {
            steps {
                echo '=== Pushing to ECR ==='
                script {
                    withAWS(credentials: 'aws-credentials', region: "${AWS_REGION}") {
                        sh """
                            aws ecr get-login-password --region ${AWS_REGION} | \
                                docker login --username AWS --password-stdin ${ECR_REGISTRY}
                            
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${IMAGE_NAME}:latest
                            
                            docker push ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${ECR_REGISTRY}/${IMAGE_NAME}:latest
                            
                            echo "✅ Image: ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                        """
                    }
                }
            }
        }
    }
    
    post {
        success {
            echo '✅ Pipeline completed!'
            echo "Image: ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo '❌ Pipeline failed!'
        }
        always {
            cleanWs()
        }
    }
}
