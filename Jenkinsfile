pipeline {
    agent any
    
    environment {
        // AWS Configuration
        AWS_REGION = 'us-east-1'
        ECR_REGISTRY = credentials('backend-ecr-registry')
        IMAGE_NAME = 'backend-app'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        
        // RDS Configuration
        RDS_DB_NAME = 'database-1'
        RDS_PORT = '5432'
    }
    
    stages {
        stage('Checkout') {
            steps {
                echo '=== 📥 Checking out code from GitHub ==='
                checkout scm
            }
        }
        
        stage('Build Dependencies') {
            steps {
                echo '=== 📦 Installing Python dependencies ==='
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
        
        stage('Setup Test Database') {
            steps {
                echo '=== 🗄️ Setting up test database in RDS ==='
                dir('backend') {
                    withCredentials([
                        string(credentialsId: 'rds-host', variable: 'RDS_HOST'),
                        string(credentialsId: 'rds-username', variable: 'RDS_USERNAME'),
                        string(credentialsId: 'rds-password', variable: 'RDS_PASSWORD')
                    ]) {
                        sh '''
                            # Set password for psql
                            export PGPASSWORD="${RDS_PASSWORD}"
                            
                            # Check if database exists, create if not
                            echo "Checking if database exists..."
                            DB_EXISTS=$(psql -h "${RDS_HOST}" \
                                 -U "${RDS_USERNAME}" \
                                 -d postgres \
                                 -tAc "SELECT 1 FROM pg_database WHERE datname = '${RDS_DB_NAME}'" || echo "0")
                            
                            if [ "$DB_EXISTS" != "1" ]; then
                                echo "Creating database ${RDS_DB_NAME}..."
                                psql -h "${RDS_HOST}" \
                                     -U "${RDS_USERNAME}" \
                                     -d postgres \
                                     -c "CREATE DATABASE ${RDS_DB_NAME};"
                                echo "✅ Database created"
                            else
                                echo "✅ Database already exists"
                            fi
                        '''
                    }
                }
            }
        }
        
        stage('Run Migrations') {
            steps {
                echo '=== 🔄 Running database migrations on RDS ==='
                dir('backend') {
                    withCredentials([
                        string(credentialsId: 'rds-host', variable: 'RDS_HOST'),
                        string(credentialsId: 'rds-username', variable: 'RDS_USERNAME'),
                        string(credentialsId: 'rds-password', variable: 'RDS_PASSWORD')
                    ]) {
                        sh '''
                            . venv/bin/activate
                            
                            # Set Django environment variables
                            export DJANGO_SETTINGS_MODULE=gig_router.settings
                            export SECRET_KEY=test-secret-key-for-ci-${BUILD_NUMBER}
                            export DEBUG=False
                            export ALLOWED_HOSTS=localhost,127.0.0.1
                            
                            # RDS Database configuration
                            export DB_ENGINE=django.db.backends.postgresql
                            export DB_NAME=${RDS_DB_NAME}
                            export DB_USER=${RDS_USERNAME}
                            export DB_PASSWORD=${RDS_PASSWORD}
                            export DB_HOST=${RDS_HOST}
                            export DB_PORT=${RDS_PORT}
                            
                            # Additional required settings
                            export REDIS_URL=redis://localhost:6379/0
                            export OPENAI_API_KEY=test-key-placeholder
                            
                            # Run migrations
                            echo "Running migrations..."
                            python manage.py migrate --noinput
                            
                            echo "✅ Migrations completed successfully"
                        '''
                    }
                }
            }
        }
        
        stage('Run Tests') {
            steps {
                echo '=== 🧪 Running Tests with RDS Database ==='
                dir('backend') {
                    withCredentials([
                        string(credentialsId: 'rds-host', variable: 'RDS_HOST'),
                        string(credentialsId: 'rds-username', variable: 'RDS_USERNAME'),
                        string(credentialsId: 'rds-password', variable: 'RDS_PASSWORD')
                    ]) {
                        sh '''
                            . venv/bin/activate
                            
                            # Django settings
                            export DJANGO_SETTINGS_MODULE=gig_router.settings
                            export SECRET_KEY=test-secret-key-for-ci-${BUILD_NUMBER}
                            export DEBUG=False
                            export ALLOWED_HOSTS=localhost,127.0.0.1
                            
                            # RDS Database configuration
                            export DB_ENGINE=django.db.backends.postgresql
                            export DB_NAME=${RDS_DB_NAME}
                            export DB_USER=${RDS_USERNAME}
                            export DB_PASSWORD=${RDS_PASSWORD}
                            export DB_HOST=${RDS_HOST}
                            export DB_PORT=${RDS_PORT}
                            
                            # Additional settings
                            export REDIS_URL=redis://localhost:6379/0
                            export OPENAI_API_KEY=test-key-placeholder
                            
                            # Create test results directory
                            mkdir -p test-results
                            
                            # Run tests with coverage
                            echo "Running pytest..."
                            pytest -v \
                                   --junitxml=test-results/pytest-report.xml \
                                   --cov=. \
                                   --cov-report=xml \
                                   --cov-report=html \
                                   --cov-report=term-missing
                            
                            echo "✅ Tests completed successfully"
                        '''
                    }
                }
            }
            post {
                always {
                    // Publish test results
                    junit 'backend/test-results/pytest-report.xml'
                    
                    // Publish coverage report
                    publishHTML([
                        allowMissing: false,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'backend/htmlcov',
                        reportFiles: 'index.html',
                        reportName: 'Coverage Report',
                        reportTitles: 'Code Coverage'
                    ])
                }
            }
        }
        
        stage('Cleanup Test Data') {
            steps {
                echo '=== 🧹 Cleaning up test data from RDS ==='
                dir('backend') {
                    withCredentials([
                        string(credentialsId: 'rds-host', variable: 'RDS_HOST'),
                        string(credentialsId: 'rds-username', variable: 'RDS_USERNAME'),
                        string(credentialsId: 'rds-password', variable: 'RDS_PASSWORD')
                    ]) {
                        sh '''
                            . venv/bin/activate
                            
                            # Set Django environment
                            export DJANGO_SETTINGS_MODULE=gig_router.settings
                            export SECRET_KEY=test-secret-key-for-ci-${BUILD_NUMBER}
                            export DB_ENGINE=django.db.backends.postgresql
                            export DB_NAME=${RDS_DB_NAME}
                            export DB_USER=${RDS_USERNAME}
                            export DB_PASSWORD=${RDS_PASSWORD}
                            export DB_HOST=${RDS_HOST}
                            export DB_PORT=${RDS_PORT}
                            
                            # Flush test database (delete all data)
                            echo "Flushing test database..."
                            python manage.py flush --noinput
                            
                            echo "✅ Test data cleaned successfully"
                        '''
                    }
                }
            }
        }
        
        stage('SonarQube Analysis') {
            steps {
                echo '=== 📊 Running SonarQube Code Quality Analysis ==='
                dir('backend') {
                    script {
                        withSonarQubeEnv('SonarQube') {
                            sh '''
                                sonar-scanner \
                                    -Dsonar.projectKey=gig-router-backend \
                                    -Dsonar.projectName="Gig Router Backend" \
                                    -Dsonar.sources=. \
                                    -Dsonar.exclusions=**/migrations/**,**/tests.py,**/tests/**,**/static/**,**/venv/**,**/__pycache__/** \
                                    -Dsonar.python.coverage.reportPaths=coverage.xml \
                                    -Dsonar.python.version=3.11
                            '''
                        }
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
                            error "❌ Pipeline aborted due to quality gate failure: ${qg.status}"
                        }
                        echo "✅ Quality Gate passed"
                    }
                }
            }
        }
        
        stage('OWASP Dependency Check') {
            steps {
                echo '=== 🔒 Running OWASP Dependency Security Check ==='
                dependencyCheck additionalArguments: '''
                    --scan backend/
                    --format XML 
                    --format HTML
                    --project gig-router-backend
                    --failOnCVSS 8
                    --suppression backend/dependency-check-suppression.xml
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
                echo '=== 🐳 Building Docker Image ==='
                dir('backend') {
                    script {
                        sh """
                            echo "Building image: ${IMAGE_NAME}:${IMAGE_TAG}"
                            
                            docker build \
                                --build-arg BUILD_DATE=\$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                                --build-arg VCS_REF=\$(git rev-parse --short HEAD) \
                                --build-arg BUILD_VERSION=${IMAGE_TAG} \
                                -t ${IMAGE_NAME}:${IMAGE_TAG} \
                                -t ${IMAGE_NAME}:latest \
                                .
                            
                            echo "✅ Docker image built successfully"
                            docker images | grep ${IMAGE_NAME}
                        """
                    }
                }
            }
        }
        
        stage('Trivy Image Scan') {
            steps {
                echo '=== 🔍 Scanning Docker Image with Trivy ==='
                script {
                    sh """
                        echo "Scanning image: ${IMAGE_NAME}:${IMAGE_TAG}"
                        
                        # Run Trivy scan
                        trivy image \
                            --severity HIGH,CRITICAL \
                            --format json \
                            --output trivy-report.json \
                            ${IMAGE_NAME}:${IMAGE_TAG}
                        
                        # Display summary
                        echo "=== Trivy Scan Summary ==="
                        trivy image \
                            --severity HIGH,CRITICAL \
                            --format table \
                            ${IMAGE_NAME}:${IMAGE_TAG}
                        
                        # Check for critical vulnerabilities
                        CRITICAL_COUNT=\$(jq '[.Results[]?.Vulnerabilities[]? | select(.Severity=="CRITICAL")] | length' trivy-report.json)
                        echo "Critical vulnerabilities found: \$CRITICAL_COUNT"
                        
                        if [ "\$CRITICAL_COUNT" -gt "0" ]; then
                            echo "⚠️ Warning: \$CRITICAL_COUNT critical vulnerabilities found"
                            # Uncomment to fail on critical vulnerabilities:
                            # exit 1
                        fi
                        
                        echo "✅ Image scan completed"
                    """
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
                }
            }
        }
        
        stage('Push to ECR') {
            steps {
                echo '=== 📤 Pushing Docker Image to AWS ECR ==='
                script {
                    withAWS(credentials: 'aws-credentials', region: "${AWS_REGION}") {
                        sh """
                            echo "Logging in to ECR..."
                            aws ecr get-login-password --region ${AWS_REGION} | \
                                docker login --username AWS --password-stdin ${ECR_REGISTRY}
                            
                            echo "Tagging images..."
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${IMAGE_NAME}:latest
                            
                            echo "Pushing images to ECR..."
                            docker push ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
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
            echo '=== 🧹 Cleaning up workspace ==='
            // Clean up Docker images to save space
            sh """
                docker rmi ${IMAGE_NAME}:${IMAGE_TAG} || true
                docker rmi ${IMAGE_NAME}:latest || true
                docker rmi ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG} || true
                docker rmi ${ECR_REGISTRY}/${IMAGE_NAME}:latest || true
            """
            cleanWs()
        }
        
        success {
            echo '✅ ========================================='
            echo '✅ Pipeline completed successfully!'
            echo '✅ ========================================='
            echo "📦 Docker Image: ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
            echo "🏷️  Build Number: ${BUILD_NUMBER}"
            echo "🌿 Git Branch: ${env.GIT_BRANCH}"
            echo "📝 Git Commit: ${env.GIT_COMMIT}"
            echo '✅ ========================================='
            
            // Optional: Send success notification
            // emailext(
            //     subject: "✅ Jenkins Build Success: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
            //     body: "Build succeeded!\n\nImage: ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}",
            //     to: "team@example.com"
            // )
        }
        
        failure {
            echo '❌ ========================================='
            echo '❌ Pipeline failed!'
            echo '❌ ========================================='
            echo "🔍 Check logs above for error details"
            echo "🏷️  Failed Build: ${BUILD_NUMBER}"
            echo '❌ ========================================='
            
            // Optional: Cleanup test database on failure
            script {
                try {
                    dir('backend') {
                        withCredentials([
                            string(credentialsId: 'rds-host', variable: 'RDS_HOST'),
                            string(credentialsId: 'rds-username', variable: 'RDS_USERNAME'),
                            string(credentialsId: 'rds-password', variable: 'RDS_PASSWORD')
                        ]) {
                            sh '''
                                . venv/bin/activate || true
                                export DJANGO_SETTINGS_MODULE=gig_router.settings
                                export SECRET_KEY=test-secret-key-for-ci-${BUILD_NUMBER}
                                export DB_ENGINE=django.db.backends.postgresql
                                export DB_NAME=${RDS_DB_NAME}
                                export DB_USER=${RDS_USERNAME}
                                export DB_PASSWORD=${RDS_PASSWORD}
                                export DB_HOST=${RDS_HOST}
                                export DB_PORT=${RDS_PORT}
                                python manage.py flush --noinput || true
                            '''
                        }
                    }
                } catch (Exception e) {
                    echo "⚠️ Warning: Could not clean up test database: ${e.message}"
                }
            }
            
            // Optional: Send failure notification
            // emailext(
            //     subject: "❌ Jenkins Build Failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}",
            //     body: "Build failed. Check console output for details.",
            //     to: "team@example.com"
            // )
        }
        
        unstable {
            echo '⚠️ Pipeline completed with warnings'
        }
    }
}
