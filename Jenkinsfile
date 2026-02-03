pipeline {
    agent any
    
    environment {
        // AWS Configuration
        AWS_REGION = 'us-east-1'
        ECR_REGISTRY = credentials('backend-ecr-registry')
        IMAGE_NAME = 'backend-app'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        
        // RDS Configuration
        RDS_SECRET_ARN = 'arn:aws:secretsmanager:us-east-1:517757113300:secret:rdsdb-ddb17298-ba46-433c-9bd2-bace0ff67ad0-HTNMRY'
        RDS_DB_NAME = 'gig_router_test'
        RDS_PORT = '5432'
        
        // Python
        PYTHON_VERSION = '3.11'
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 1, unit: 'HOURS')
        disableConcurrentBuilds()
    }
    
    stages {
        stage('Cleanup Workspace') {
            steps {
                echo '=== 🧹 Cleaning workspace ==='
                cleanWs()
            }
        }
        
        stage('Checkout Code') {
            steps {
                echo '=== 📥 Checking out code from GitHub ==='
                checkout scm
                script {
                    env.GIT_COMMIT_SHORT = sh(
                        returnStdout: true,
                        script: 'git rev-parse --short HEAD'
                    ).trim()
                    
                    echo "Branch: ${env.GIT_BRANCH}"
                    echo "Commit: ${env.GIT_COMMIT}"
                    echo "Short Commit: ${env.GIT_COMMIT_SHORT}"
                }
            }
        }
        
        stage('Get RDS Credentials') {
            steps {
                echo '=== 🔐 Retrieving RDS credentials from AWS Secrets Manager ==='
                script {
                    withAWS(credentials: 'aws-credentials', region: "${AWS_REGION}") {
                        def secretJson = sh(
                            returnStdout: true,
                            script: """
                                aws secretsmanager get-secret-value \
                                    --secret-id '${RDS_SECRET_ARN}' \
                                    --region ${AWS_REGION} \
                                    --query SecretString \
                                    --output text
                            """
                        ).trim()
                        
                        def secret = readJSON text: secretJson
                        
                        env.DB_HOST = secret.host
                        env.DB_PORT = secret.port ?: '5432'
                        env.DB_NAME = RDS_DB_NAME
                        env.DB_USER = secret.username
                        env.DB_PASSWORD = secret.password
                        env.DB_ENGINE = 'django.db.backends.postgresql'
                        
                        echo "✅ RDS Configuration loaded:"
                        echo "   Host: ${env.DB_HOST}"
                        echo "   Port: ${env.DB_PORT}"
                        echo "   Database: ${env.DB_NAME}"
                        echo "   User: ${env.DB_USER}"
                    }
                }
            }
        }
        
        stage('Setup Python Environment') {
            steps {
                echo '=== 🐍 Setting up Python virtual environment ==='
                dir('backend') {
                    sh '''
                        python3 --version
                        python3 -m venv venv
                        . venv/bin/activate
                        pip install --upgrade pip
                        pip install -r requirements.txt
                        pip list
                    '''
                }
            }
        }
        
        stage('Test RDS Connection') {
            steps {
                echo '=== ���� Testing RDS database connection ==='
                dir('backend') {
                    sh '''
                        . venv/bin/activate
                        
                        cat > test_db_connection.py << 'PYEOF'
import os
import sys
import psycopg2

try:
    conn = psycopg2.connect(
        host=os.environ['DB_HOST'],
        port=os.environ.get('DB_PORT', '5432'),
        database='postgres',
        user=os.environ['DB_USER'],
        password=os.environ['DB_PASSWORD']
    )
    cursor = conn.cursor()
    cursor.execute('SELECT version();')
    version = cursor.fetchone()
    print(f"✅ Successfully connected to PostgreSQL!")
    print(f"Database version: {version[0]}")
    cursor.close()
    conn.close()
    sys.exit(0)
except Exception as e:
    print(f"❌ Failed to connect to database: {str(e)}")
    sys.exit(1)
PYEOF
                        
                        python test_db_connection.py
                    '''
                }
            }
        }
        
        stage('Setup Test Database') {
            steps {
                echo '=== 🗄️ Setting up test database in RDS ==='
                dir('backend') {
                    sh '''
                        . venv/bin/activate
                        export PGPASSWORD="${DB_PASSWORD}"
                        
                        echo "Checking if database exists..."
                        DB_EXISTS=$(psql -h "${DB_HOST}" -U "${DB_USER}" -d postgres \
                            -tAc "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}'" || echo "0")
                        
                        if [ "$DB_EXISTS" != "1" ]; then
                            echo "Creating database ${DB_NAME}..."
                            psql -h "${DB_HOST}" -U "${DB_USER}" -d postgres \
                                -c "CREATE DATABASE ${DB_NAME};"
                            echo "✅ Database created"
                        else
                            echo "✅ Database already exists"
                        fi
                    '''
                }
            }
        }
        
        stage('Run Migrations') {
            steps {
                echo '=== 🔄 Running Django database migrations ==='
                dir('backend') {
                    sh '''
                        . venv/bin/activate
                        
                        export DJANGO_SETTINGS_MODULE=gig_router.settings
                        export SECRET_KEY=jenkins-ci-test-key-${BUILD_NUMBER}
                        export DEBUG=False
                        export ALLOWED_HOSTS=localhost,127.0.0.1
                        export DB_ENGINE=${DB_ENGINE}
                        export DB_NAME=${DB_NAME}
                        export DB_USER=${DB_USER}
                        export DB_PASSWORD=${DB_PASSWORD}
                        export DB_HOST=${DB_HOST}
                        export DB_PORT=${DB_PORT}
                        export REDIS_URL=redis://localhost:6379/0
                        export OPENAI_API_KEY=test-key
                        
                        echo "Checking migrations..."
                        python manage.py showmigrations
                        
                        echo "Running migrations..."
                        python manage.py migrate --noinput
                        
                        echo "✅ Migrations completed successfully"
                    '''
                }
            }
        }
        
        stage('Run Tests') {
            steps {
                echo '=== 🧪 Running tests with RDS database ==='
                dir('backend') {
                    sh '''
                        . venv/bin/activate
                        
                        export DJANGO_SETTINGS_MODULE=gig_router.settings
                        export SECRET_KEY=jenkins-ci-test-key-${BUILD_NUMBER}
                        export DEBUG=False
                        export ALLOWED_HOSTS=localhost
                        export DB_ENGINE=${DB_ENGINE}
                        export DB_NAME=${DB_NAME}
                        export DB_USER=${DB_USER}
                        export DB_PASSWORD=${DB_PASSWORD}
                        export DB_HOST=${DB_HOST}
                        export DB_PORT=${DB_PORT}
                        export REDIS_URL=redis://localhost:6379/0
                        export OPENAI_API_KEY=test-key
                        
                        mkdir -p test-results
                        
                        pytest -v \
                            --junitxml=test-results/junit.xml \
                            --cov=. \
                            --cov-report=xml \
                            --cov-report=html \
                            --cov-report=term-missing
                    '''
                }
            }
            post {
                always {
                    junit 'backend/test-results/junit.xml'
                    publishHTML([
                        allowMissing: true,
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
                echo '=== 🧹 Cleaning up test data ==='
                dir('backend') {
                    sh '''
                        . venv/bin/activate
                        
                        export DJANGO_SETTINGS_MODULE=gig_router.settings
                        export SECRET_KEY=jenkins-ci-test-key-${BUILD_NUMBER}
                        export DB_ENGINE=${DB_ENGINE}
                        export DB_NAME=${DB_NAME}
                        export DB_USER=${DB_USER}
                        export DB_PASSWORD=${DB_PASSWORD}
                        export DB_HOST=${DB_HOST}
                        export DB_PORT=${DB_PORT}
                        
                        python manage.py flush --noinput
                        echo "✅ Test data cleaned"
                    '''
                }
            }
        }
        
        stage('SonarQube Analysis') {
            steps {
                echo '=== 📊 Running SonarQube analysis ==='
                dir('backend') {
                    withSonarQubeEnv('SonarQube') {
                        sh '''
                            sonar-scanner \
                                -Dsonar.projectKey=gig-router-backend \
                                -Dsonar.projectName="Gig Router Backend" \
                                -Dsonar.sources=. \
                                -Dsonar.exclusions=**/migrations/**,**/tests.py,**/tests/**,**/venv/**,**/__pycache__/** \
                                -Dsonar.python.coverage.reportPaths=coverage.xml \
                                -Dsonar.python.version=3.11
                        '''
                    }
                }
            }
        }
        
        stage('Quality Gate') {
            steps {
                echo '=== 🚦 Waiting for SonarQube Quality Gate ==='
                timeout(time: 5, unit: 'MINUTES') {
                    script {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            error "❌ Quality gate failure: ${qg.status}"
                        }
                        echo "✅ Quality Gate passed"
                    }
                }
            }
        }
        
        stage('OWASP Dependency Check') {
            steps {
                echo '=== 🔒 Running OWASP Dependency Check ==='
                dependencyCheck additionalArguments: '''
                    --scan backend/
                    --format XML
                    --format HTML
                    --project gig-router-backend
                    --failOnCVSS 8
                ''', odcInstallation: 'OWASP-DC'
            }
            post {
                always {
                    dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                echo '=== 🐳 Building Docker image ==='
                dir('backend') {
                    sh """
                        chmod +x entrypoint.sh
                        
                        docker build \
                            -t ${IMAGE_NAME}:${IMAGE_TAG} \
                            -t ${IMAGE_NAME}:${env.GIT_COMMIT_SHORT} \
                            -t ${IMAGE_NAME}:latest \
                            --build-arg BUILD_DATE=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                            --build-arg VCS_REF=${env.GIT_COMMIT_SHORT} \
                            --build-arg VERSION=${IMAGE_TAG} \
                            .
                        
                        echo "✅ Docker image built successfully"
                        docker images | grep ${IMAGE_NAME}
                    """
                }
            }
        }
        
        stage('Trivy Image Scan') {
            steps {
                echo '=== 🔍 Scanning Docker image with Trivy ==='
                sh """
                    mkdir -p trivy-reports
                    
                    trivy image \
                        --severity HIGH,CRITICAL \
                        --format json \
                        --output trivy-reports/trivy-report.json \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                    
                    trivy image \
                        --severity HIGH,CRITICAL \
                        --format table \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                    
                    echo "✅ Image scan completed"
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-reports/*', allowEmptyArchive: true
                }
            }
        }
        
        stage('Push to ECR') {
            steps {
                echo '=== 📤 Pushing Docker image to AWS ECR ==='
                script {
                    withAWS(credentials: 'aws-credentials', region: "${AWS_REGION}") {
                        sh """
                            echo "Logging in to ECR..."
                            aws ecr get-login-password --region ${AWS_REGION} | \
                                docker login --username AWS --password-stdin ${ECR_REGISTRY}
                            
                            echo "Tagging images..."
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${IMAGE_NAME}:${env.GIT_COMMIT_SHORT}
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${IMAGE_NAME}:latest
                            
                            echo "Pushing images to ECR..."
                            docker push ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${ECR_REGISTRY}/${IMAGE_NAME}:${env.GIT_COMMIT_SHORT}
                            docker push ${ECR_REGISTRY}/${IMAGE_NAME}:latest
                            
                            echo "✅ Images pushed successfully!"
                            echo "📦 Image URI: ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                        """
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo '=== 🧹 Cleaning up Docker images ==='
            sh """
                docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                docker rmi ${IMAGE_NAME}:${env.GIT_COMMIT_SHORT} || true
                docker rmi ${IMAGE_NAME}:latest || true
                docker rmi ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} || true
                docker rmi ${ECR_REGISTRY}/${IMAGE_NAME}:${env.GIT_COMMIT_SHORT} || true
                docker rmi ${ECR_REGISTRY}/${IMAGE_NAME}:latest || true
            """
        }
        
        success {
            echo '✅ =========================================='
            echo '✅ Pipeline completed successfully!'
            echo '✅ =========================================='
            echo "✅ Build Number: ${BUILD_NUMBER}"
            echo "✅ Git Commit: ${env.GIT_COMMIT_SHORT}"
            echo "✅ Docker Image: ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
            echo "✅ RDS Database: ${env.DB_HOST}"
            echo '✅ =========================================='
        }
        
        failure {
            echo '❌ =========================================='
            echo '❌ Pipeline failed!'
            echo '❌ =========================================='
            echo '❌ Check the logs above for errors'
            echo '❌ =========================================='
        }
        
        cleanup {
            cleanWs()
        }
    }
}
