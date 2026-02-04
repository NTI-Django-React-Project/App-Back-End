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
                    
                    # Install pytest with Django support
                    pip install pytest pytest-django pytest-cov pytest-xdist
                    pip install factory-boy Faker
                    '''
                }
            }
        }

        stage('Run Django Migrations') {
            steps {
                dir('backend') {
                    sh '''
                    . venv/bin/activate

                    echo "Creating migrations..."
                    python manage.py makemigrations --noinput || echo "No new migrations to create"

                    echo "Applying migrations to main database..."
                    python manage.py migrate --noinput
                    
                    echo "Migrations completed!"
                    '''
                }
            }
        }

        stage('Setup Test Database') {
            steps {
                dir('backend') {
                    sh '''
                    . venv/bin/activate
                    
                    # Create a test-specific database
                    echo "Setting up test database..."
                    
                    # Option 1: Use Django's test setup
                    python manage.py flush --noinput
                    python manage.py migrate --noinput
                    
                    # Option 2: Or create test database directly
                    # PGPASSWORD=${DB_PASSWORD} psql -h ${DB_HOST} -U ${DB_USER} -p ${DB_PORT} -c "CREATE DATABASE test_${DB_NAME};"
                    
                    echo "Test database ready!"
                    '''
                }
            }
        }

        stage('Run Tests with Django Test Runner') {
            steps {
                dir('backend') {
                    sh '''
                    . venv/bin/activate
                    
                    # First run Django's test runner to ensure database is set up
                    echo "Running Django tests..."
                    python manage.py test --noinput --parallel=4
                    '''
                }
            }
        }

        stage('Run Tests with Pytest for Coverage') {
            steps {
                dir('backend') {
                    sh '''
                    . venv/bin/activate
                    
                    # Run tests with coverage - use --reuse-db to reuse the test database
                    pytest \
                        --ds=gig_router.settings \
                        --cov=. \
                        --cov-report=xml:coverage.xml \
                        --cov-report=html:htmlcov \
                        --cov-report=term \
                        --junitxml=junit-results.xml \
                        --disable-warnings \
                        --reuse-db \
                        --create-db \
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

        stage('Quality Gate') {
            steps {
                timeout(time: 15, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
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
