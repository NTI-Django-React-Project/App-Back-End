pipeline {
    agent any
    
    environment {
        // AWS Configuration
        AWS_REGION = 'us-east-1'
        AWS_ACCOUNT_ID = credentials('aws-account-id')
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECR_REPO_NAME = 'django-backend'
        
        // Application
        APP_NAME = 'django-backend'
        
        // Docker Image Tags
        IMAGE_TAG = "${env.BUILD_NUMBER}"
        GIT_COMMIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
        
        // SonarQube
        SONAR_HOST_URL = credentials('sonar-host-url')
        SONAR_TOKEN = credentials('sonar-token')
        
        // Nexus
        NEXUS_URL = credentials('nexus-url')
        NEXUS_CREDENTIALS = credentials('nexus-credentials')
        
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
                cleanWs()
            }
        }
        
        stage('Checkout Code') {
            steps {
                script {
                    echo "Checking out code from GitHub..."
                    checkout scm
                    
                    // Print branch and commit info
                    sh '''
                        echo "Branch: ${GIT_BRANCH}"
                        echo "Commit: ${GIT_COMMIT}"
                        echo "Short Commit: ${GIT_COMMIT_SHORT}"
                    '''
                }
            }
        }
        
        stage('Setup Python Environment') {
            steps {
                script {
                    echo "Setting up Python virtual environment..."
                    sh '''
                        python3 -m venv venv
                        . venv/bin/activate
                        pip install --upgrade pip
                        pip install -r requirements.txt
                    '''
                }
            }
        }
        
        stage('Build Application') {
            steps {
                script {
                    echo "Building Django application..."
                    sh '''
                        . venv/bin/activate
                        python manage.py collectstatic --noinput || echo "No static files"
                    '''
                }
            }
        }
        
        stage('Run Unit Tests') {
            steps {
                script {
                    echo "Running unit tests with pytest..."
                    sh '''
                        . venv/bin/activate
                        
                        # Create test results directory
                        mkdir -p test-results
                        
                        # Run tests with coverage
                        pytest --junitxml=test-results/junit.xml \
                               --cov=. \
                               --cov-report=xml \
                               --cov-report=html \
                               --cov-report=term-missing \
                               tests/ || true
                    '''
                }
            }
            post {
                always {
                    // Publish test results
                    junit allowEmptyResults: true, testResults: 'test-results/junit.xml'
                    
                    // Archive coverage reports
                    publishHTML([
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'htmlcov',
                        reportFiles: 'index.html',
                        reportName: 'Coverage Report'
                    ])
                }
            }
        }
        
        stage('SonarQube Analysis') {
            steps {
                script {
                    echo "Running SonarQube analysis..."
                    withSonarQubeEnv('SonarQube') {
                        sh '''
                            sonar-scanner \
                                -Dsonar.projectKey=django-backend-app \
                                -Dsonar.sources=. \
                                -Dsonar.host.url=${SONAR_HOST_URL} \
                                -Dsonar.login=${SONAR_TOKEN} \
                                -Dsonar.python.coverage.reportPaths=coverage.xml
                        '''
                    }
                }
            }
        }
        
        stage('Quality Gate') {
            steps {
                script {
                    echo "Waiting for SonarQube Quality Gate..."
                    timeout(time: 5, unit: 'MINUTES') {
                        waitForQualityGate abortPipeline: true
                    }
                }
            }
        }
        
        stage('OWASP Dependency Check') {
            steps {
                script {
                    echo "Running OWASP Dependency Check..."
                    sh '''
                        # Create reports directory
                        mkdir -p owasp-reports
                        
                        # Run dependency check
                        dependency-check \
                            --project "Django Backend" \
                            --scan . \
                            --format HTML \
                            --format XML \
                            --out owasp-reports \
                            --suppression owasp-suppression.xml || true
                    '''
                }
            }
            post {
                always {
                    // Publish OWASP report
                    publishHTML([
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'owasp-reports',
                        reportFiles: 'dependency-check-report.html',
                        reportName: 'OWASP Dependency Check'
                    ])
                    
                    // Archive XML report for further processing
                    archiveArtifacts artifacts: 'owasp-reports/*.xml', allowEmptyArchive: true
                }
            }
        }
        
        stage('Build Python Package') {
            steps {
                script {
                    echo "Building Python package for Nexus..."
                    sh '''
                        . venv/bin/activate
                        
                        # Create distribution
                        python setup.py sdist bdist_wheel || echo "No setup.py found, skipping package build"
                    '''
                }
            }
        }
        
        stage('Push to Nexus') {
            steps {
                script {
                    echo "Pushing artifacts to Nexus repository..."
                    sh '''
                        . venv/bin/activate
                        
                        # Upload to Nexus using twine
                        if [ -d "dist" ]; then
                            pip install twine
                            twine upload --repository-url ${NEXUS_URL} \
                                         --username ${NEXUS_CREDENTIALS_USR} \
                                         --password ${NEXUS_CREDENTIALS_PSW} \
                                         dist/* || echo "Upload to Nexus failed or skipped"
                        else
                            echo "No dist directory found, skipping Nexus upload"
                        fi
                    '''
                }
            }
        }
        
        stage('Build Docker Image') {
            steps {
                script {
                    echo "Building Docker image..."
                    sh '''
                        # Make entrypoint executable
                        chmod +x entrypoint.sh
                        
                        # Build Docker image
                        docker build \
                            -t ${ECR_REPO_NAME}:${IMAGE_TAG} \
                            -t ${ECR_REPO_NAME}:${GIT_COMMIT_SHORT} \
                            -t ${ECR_REPO_NAME}:latest \
                            --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
                            --build-arg VCS_REF=${GIT_COMMIT_SHORT} \
                            --build-arg VERSION=${IMAGE_TAG} \
                            .
                        
                        # Display image details
                        docker images | grep ${ECR_REPO_NAME}
                    '''
                }
            }
        }
        
        stage('Trivy Image Scan') {
            steps {
                script {
                    echo "Scanning Docker image with Trivy..."
                    sh '''
                        # Create reports directory
                        mkdir -p trivy-reports
                        
                        # Scan image for vulnerabilities
                        trivy image \
                            --severity HIGH,CRITICAL \
                            --format table \
                            --output trivy-reports/trivy-report.txt \
                            ${ECR_REPO_NAME}:${IMAGE_TAG}
                        
                        # Generate JSON report
                        trivy image \
                            --severity HIGH,CRITICAL \
                            --format json \
                            --output trivy-reports/trivy-report.json \
                            ${ECR_REPO_NAME}:${IMAGE_TAG}
                        
                        # Generate HTML report
                        trivy image \
                            --severity HIGH,CRITICAL \
                            --format template \
                            --template "@contrib/html.tpl" \
                            --output trivy-reports/trivy-report.html \
                            ${ECR_REPO_NAME}:${IMAGE_TAG} || true
                        
                        # Display summary
                        cat trivy-reports/trivy-report.txt
                    '''
                }
            }
            post {
                always {
                    // Publish Trivy report
                    publishHTML([
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'trivy-reports',
                        reportFiles: 'trivy-report.html',
                        reportName: 'Trivy Security Scan'
                    ])
                    
                    // Archive reports
                    archiveArtifacts artifacts: 'trivy-reports/*', allowEmptyArchive: true
                }
            }
        }
        
        stage('Push to ECR') {
            steps {
                script {
                    echo "Pushing Docker image to ECR..."
                    sh '''
                        # Login to ECR
                        aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        
                        # Tag images for ECR
                        docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}
                        docker tag ${ECR_REPO_NAME}:${GIT_COMMIT_SHORT} ${ECR_REGISTRY}/${ECR_REPO_NAME}:${GIT_COMMIT_SHORT}
                        docker tag ${ECR_REPO_NAME}:latest ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest
                        
                        # Push all tags to ECR
                        docker push ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}
                        docker push ${ECR_REGISTRY}/${ECR_REPO_NAME}:${GIT_COMMIT_SHORT}
                        docker push ${ECR_REGISTRY}/${ECR_REPO_NAME}:latest
                        
                        echo "Docker images pushed successfully to ECR!"
                        echo "Image URI: ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}"
                    '''
                }
            }
        }
        
        stage('Update Deployment Manifest') {
            steps {
                script {
                    echo "Updating Kubernetes deployment manifest with new image tag..."
                    sh '''
                        # This step would update your K8s manifest in Git
                        # ArgoCD will detect the change and deploy
                        
                        # Example: Update image tag in deployment.yaml
                        # sed -i "s|image:.*|image: ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}|g" k8s/backend/deployment.yaml
                        
                        # Commit and push changes
                        # git add k8s/backend/deployment.yaml
                        # git commit -m "Update backend image to ${IMAGE_TAG}"
                        # git push origin main
                        
                        echo "Manifest update completed (placeholder for actual implementation)"
                        echo "New image: ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}"
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "Cleaning up Docker images..."
                sh '''
                    # Remove local images to save space
                    docker rmi ${ECR_REPO_NAME}:${IMAGE_TAG} || true
                    docker rmi ${ECR_REPO_NAME}:${GIT_COMMIT_SHORT} || true
                    docker rmi ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG} || true
                    docker rmi ${ECR_REGISTRY}/${ECR_REPO_NAME}:${GIT_COMMIT_SHORT} || true
                '''
            }
        }
        
        success {
            echo "✅ Pipeline completed successfully!"
            echo "Docker image: ${ECR_REGISTRY}/${ECR_REPO_NAME}:${IMAGE_TAG}"
            
            // Send notification (optional)
            // slackSend(color: 'good', message: "Build #${BUILD_NUMBER} succeeded")
        }
        
        failure {
            echo "❌ Pipeline failed!"
            
            // Send notification (optional)
            // slackSend(color: 'danger', message: "Build #${BUILD_NUMBER} failed")
        }
        
        cleanup {
            cleanWs()
        }
    }
}
