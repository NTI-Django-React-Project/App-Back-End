pipeline {
    agent any

    environment {
        AWS_REGION = 'us-east-1'
        APP_NAME = 'django-backend'
        ECR_REPO = 'django-backend'

        // Use the SAME settings as your working docker-compose
        DB_ENGINE = 'django.db.backends.postgresql'
        DB_NAME = 'gig_router_db'
        DB_USER = 'postgres'
        DB_PASSWORD = 'postgres123'
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

                # Use PostgreSQL 18.1 (same as your docker-compose)
                docker run -d \
                  --name ci-postgres \
                  -e POSTGRES_DB=${DB_NAME} \
                  -e POSTGRES_USER=${DB_USER} \
                  -e POSTGRES_PASSWORD=${DB_PASSWORD} \
                  -p 5432:5432 \
                  postgres:18.1

                echo "Waiting for Postgres to be ready..."
                for i in {1..30}; do
                  if docker exec ci-postgres pg_isready -U ${DB_USER} 2>/dev/null; then
                    echo "PostgreSQL is ready!"
                    break
                  fi
                  echo "Waiting for PostgreSQL... (attempt $i/30)"
                  sleep 2
                done
                
                # Give PostgreSQL time to initialize
                sleep 5
                '''
            }
        }

        stage('Setup Python Environment') {
            steps {
                dir('backend') {
                    sh '''
                    # Create virtual environment
                    python3 -m venv venv
                    . venv/bin/activate
                    
                    # Check Python version
                    python --version
                    
                    # Install dependencies
                    pip install --upgrade pip setuptools wheel
                    pip install -r requirements.txt
                    
                    # Install test dependencies
                    pip install pytest pytest-django pytest-cov
                    '''
                }
            }
        }

        stage('Run Migrations') {
            steps {
                dir('backend') {
                    sh '''
                    . venv/bin/activate
                    
                    echo "=== Running migrations ==="
                    
                    # Make sure we're using the right database
                    echo "Using database: ${DB_NAME}"
                    echo "Using user: ${DB_USER}"
                    
                    # Run migrations
                    python manage.py migrate --noinput
                    
                    echo "=== Checking migrations ==="
                    python manage.py showmigrations
                    '''
                }
            }
        }

        stage('Run Tests') {
            steps {
                dir('backend') {
                    sh '''
                    . venv/bin/activate
                    
                    echo "=== Running tests ==="
                    
                    # Option 1: Use Django's test runner (simpler)
                    echo "Running Django tests..."
                    python manage.py test --noinput --parallel=4
                    
                    # Option 2: Run pytest for coverage
                    echo "Running pytest for coverage..."
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
                          -Dsononar.python.coverage.reportPaths=coverage.xml \
                          -Dsonar.exclusions=**/migrations/**,**/tests/** \
                          -Dsonar.tests=. \
                          -Dsonar.python.version=3.11
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

        stage('Push Image to ECR') {
            when {
                allOf {
                    branch 'main'
                    expression { 
                        currentBuild.result == null || currentBuild.result == 'SUCCESS' 
                    }
                }
            }
            steps {
                script {
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

                        aws ecr describe-repositories --repository-names ${ECR_REPO} 2>/dev/null || \
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
