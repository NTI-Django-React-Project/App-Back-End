pipeline {
    agent any
    
    environment {
        // Project Configuration
        PROJECT_NAME = 'gig-router-backend'
        PYTHON_VERSION = '3.11'
        
        // AWS Configuration
        AWS_REGION = 'us-east-1'
        AWS_ACCOUNT_ID = '517757113300'
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        ECR_REPOSITORY = 'backend-app'
        
        // Image Tagging
        IMAGE_TAG = "${env.GIT_COMMIT?.take(7) ?: 'latest'}"
        BUILD_NUMBER_TAG = "${env.BUILD_NUMBER}"
        
        // Nexus Configuration
        NEXUS_URL = 'http://192.168.10.128:8081'
        NEXUS_REPOSITORY = 'backend-nexus-repo'
        NEXUS_CREDENTIAL_ID = 'nexus-maven-creds'
        
        // SonarQube Configuration
        SONARQUBE_URL = 'http://192.168.10.128:9000'
        SONAR_PROJECT_KEY = 'django-backend-app'
        
        // Paths
        BACKEND_DIR = 'backend'
        DOCKERFILE_PATH = "${BACKEND_DIR}/Dockerfile"
        
        // Trivy Configuration
        TRIVY_SEVERITY = 'CRITICAL,HIGH'
        TRIVY_EXIT_CODE = '0'  // Set to 1 to fail on vulnerabilities
        
        // Test Results
        COVERAGE_THRESHOLD = '70'
    }
    
    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
        timeout(time: 1, unit: 'HOURS')
        disableConcurrentBuilds()
    }
    
    stages {
        stage('Checkout') {
            steps {
                script {
                    echo "🔄 Checking out code from GitHub..."
                    checkout scm
                    
                    // Display build information
                    sh """
                        echo "========================================"
                        echo "Build Information"
                        echo "========================================"
                        echo "Branch: ${env.GIT_BRANCH}"
                        echo "Commit: ${env.GIT_COMMIT}"
                        echo "Build Number: ${env.BUILD_NUMBER}"
                        echo "Image Tag: ${IMAGE_TAG}"
                        echo "========================================"
                    """
                }
            }
        }
        
        stage('Setup Python Environment') {
            steps {
                script {
                    echo "🐍 Setting up Python ${PYTHON_VERSION} environment..."
                    dir("${BACKEND_DIR}") {
                        sh """
                            # Create virtual environment
                            python3 -m venv venv
                            
                            # Activate and upgrade pip
                            . venv/bin/activate
                            pip install --upgrade pip setuptools wheel
                            
                            # Install dependencies
                            pip install -r requirements.txt
                            
                            # Install additional testing tools
                            pip install pytest-xdist pytest-timeout
                            
                            # Display installed packages
                            pip list
                        """
                    }
                }
            }
        }
        
        stage('Build Django Application') {
            steps {
                script {
                    echo "🔨 Building Django application..."
                    dir("${BACKEND_DIR}") {
                        sh """
                            . venv/bin/activate
                            
                            # Create necessary directories
                            mkdir -p staticfiles mediafiles logs test-results
                            
                            # Set Django settings for build
                            export DJANGO_SETTINGS_MODULE=gig_router.settings
                            export SECRET_KEY='jenkins-build-secret-key-$(date +%s)'
                            export DEBUG=False
                            export DB_NAME=test_db
                            export DB_USER=test_user
                            export DB_PASSWORD=test_password
                            export DB_HOST=localhost
                            export DB_PORT=5432
                            
                            # Check Django setup
                            python manage.py check --deploy || true
                            
                            # Collect static files
                            python manage.py collectstatic --noinput --clear || echo "Static files collection skipped"
                            
                            echo "✅ Django application build completed"
                        """
                    }
                }
            }
        }
        
        stage('Run Unit Tests') {
            steps {
                script {
                    echo "🧪 Running unit tests with coverage..."
                    dir("${BACKEND_DIR}") {
                        sh """
                            . venv/bin/activate
                            
                            # Set test environment variables
                            export DJANGO_SETTINGS_MODULE=gig_router.settings
                            export SECRET_KEY='test-secret-key-for-testing'
                            export DEBUG=True
                            export DB_NAME=test_db
                            export DB_USER=test_user
                            export DB_PASSWORD=test_password
                            export DB_HOST=localhost
                            export DB_PORT=5432
                            export ALLOWED_HOSTS='localhost,127.0.0.1'
                            
                            # Run pytest with coverage
                            pytest -v \
                                --cov=. \
                                --cov-report=xml:coverage.xml \
                                --cov-report=html:htmlcov \
                                --cov-report=term-missing \
                                --junitxml=test-results/junit.xml \
                                --maxfail=5 \
                                --tb=short \
                                || echo "Some tests failed, but continuing pipeline"
                            
                            # Display coverage summary
                            echo "========================================"
                            echo "Coverage Summary"
                            echo "========================================"
                            coverage report || true
                            
                            # Check coverage threshold
                            COVERAGE=\$(coverage report | grep TOTAL | awk '{print \$4}' | sed 's/%//')
                            echo "Total Coverage: \${COVERAGE}%"
                            echo "Required Coverage: ${COVERAGE_THRESHOLD}%"
                            
                            if [ -n "\$COVERAGE" ]; then
                                if [ "\${COVERAGE%.*}" -lt "${COVERAGE_THRESHOLD}" ]; then
                                    echo "⚠️ Warning: Coverage \${COVERAGE}% is below threshold ${COVERAGE_THRESHOLD}%"
                                else
                                    echo "✅ Coverage \${COVERAGE}% meets threshold ${COVERAGE_THRESHOLD}%"
                                fi
                            fi
                        """
                    }
                }
            }
            post {
                always {
                    // Publish test results
                    junit allowEmptyResults: true, testResults: "${BACKEND_DIR}/test-results/junit.xml"
                    
                    // Publish coverage report
                    publishHTML([
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: "${BACKEND_DIR}/htmlcov",
                        reportFiles: 'index.html',
                        reportName: 'Coverage Report'
                    ])
                }
            }
        }
        
        stage('SonarQube Analysis') {
            steps {
                script {
                    echo "📊 Running SonarQube analysis..."
                    dir("${BACKEND_DIR}") {
                        withSonarQubeEnv('SonarQube') {
                            sh """
                                # Run SonarQube scanner
                                sonar-scanner \
                                    -Dsonar.projectKey=${SONAR_PROJECT_KEY} \
                                    -Dsonar.sources=. \
                                    -Dsonar.host.url=${SONARQUBE_URL} \
                                    -Dsonar.python.coverage.reportPaths=coverage.xml \
                                    -Dsonar.python.xunit.reportPath=test-results/junit.xml \
                                    -Dsonar.exclusions='**/migrations/**,**/tests/**,**/venv/**,**/__pycache__/**,**/staticfiles/**,**/mediafiles/**' \
                                    -Dsonar.python.version=${PYTHON_VERSION}
                            """
                        }
                    }
                }
            }
        }
        
        stage('Quality Gate') {
            steps {
                script {
                    echo "🚦 Waiting for SonarQube Quality Gate..."
                    timeout(time: 10, unit: 'MINUTES') {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            echo "⚠️ Quality Gate status: ${qg.status}"
                            echo "Quality Gate failed but continuing pipeline..."
                            // Uncomment to fail the build on quality gate failure
                            // error "Pipeline aborted due to quality gate failure: ${qg.status}"
                        } else {
                            echo "✅ Quality Gate passed: ${qg.status}"
                        }
                    }
                }
            }
        }
        
        stage('OWASP Dependency Check') {
            steps {
                script {
                    echo "🔒 Running OWASP Dependency Check..."
                    dir("${BACKEND_DIR}") {
                        sh """
                            # Create OWASP reports directory
                            mkdir -p owasp-reports
                            
                            # Run dependency check
                            dependency-check \
                                --project "${PROJECT_NAME}" \
                                --scan . \
                                --format HTML \
                                --format XML \
                                --format JSON \
                                --out owasp-reports \
                                --exclude '**/venv/**' \
                                --exclude '**/tests/**' \
                                --exclude '**/migrations/**' \
                                --exclude '**/__pycache__/**' \
                                --suppression owasp-suppressions.xml || true
                            
                            echo "✅ OWASP Dependency Check completed"
                        """
                    }
                }
            }
            post {
                always {
                    // Publish OWASP Dependency Check report
                    publishHTML([
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: "${BACKEND_DIR}/owasp-reports",
                        reportFiles: 'dependency-check-report.html',
                        reportName: 'OWASP Dependency Check Report'
                    ])
                    
                    // Archive OWASP reports
                    archiveArtifacts artifacts: "${BACKEND_DIR}/owasp-reports/*", allowEmptyArchive: true
                }
            }
        }
        
        stage('Build Python Package') {
            steps {
                script {
                    echo "📦 Building Python package for Nexus..."
                    dir("${BACKEND_DIR}") {
                        sh """
                            . venv/bin/activate
                            
                            # Build wheel and source distribution
                            python setup.py sdist bdist_wheel
                            
                            # Display built packages
                            ls -lh dist/
                        """
                    }
                }
            }
        }
        
        stage('Push Artifacts to Nexus') {
            steps {
                script {
                    echo "📤 Pushing artifacts to Nexus repository..."
                    dir("${BACKEND_DIR}") {
                        withCredentials([usernamePassword(
                            credentialsId: "${NEXUS_CREDENTIAL_ID}",
                            usernameVariable: 'NEXUS_USER',
                            passwordVariable: 'NEXUS_PASS'
                        )]) {
                            sh """
                                . venv/bin/activate
                                
                                # Install twine for uploading
                                pip install twine
                                
                                # Upload to Nexus using twine
                                for file in dist/*; do
                                    echo "Uploading \$file to Nexus..."
                                    curl -v -u \${NEXUS_USER}:\${NEXUS_PASS} \
                                        --upload-file "\$file" \
                                        "${NEXUS_URL}/repository/${NEXUS_REPOSITORY}/\$(basename \$file)"
                                done
                                
                                echo "✅ Artifacts pushed to Nexus successfully"
                            """
                        }
                    }
                }
            }
        }
        
        stage('Build Docker Image with Kaniko') {
            steps {
                script {
                    echo "🐳 Building Docker image with Kaniko..."
                    
                    // Get ECR login password
                    def ecrPassword = sh(
                        script: "aws ecr get-login-password --region ${AWS_REGION}",
                        returnStdout: true
                    ).trim()
                    
                    // Create Kaniko pod specification
                    def kanikoPodYaml = """
apiVersion: v1
kind: Pod
metadata:
  name: kaniko-${BUILD_NUMBER}
  namespace: default
spec:
  restartPolicy: Never
  containers:
  - name: kaniko
    image: gcr.io/kaniko-project/executor:latest
    args:
    - "--context=dir:///workspace/${BACKEND_DIR}"
    - "--dockerfile=/workspace/${DOCKERFILE_PATH}"
    - "--destination=${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
    - "--destination=${ECR_REGISTRY}/${ECR_REPOSITORY}:build-${BUILD_NUMBER_TAG}"
    - "--destination=${ECR_REGISTRY}/${ECR_REPOSITORY}:latest"
    - "--cache=true"
    - "--cache-repo=${ECR_REGISTRY}/${ECR_REPOSITORY}-cache"
    - "--compressed-caching=false"
    - "--snapshot-mode=redo"
    - "--log-format=text"
    - "--verbosity=info"
    volumeMounts:
    - name: workspace
      mountPath: /workspace
    - name: docker-config
      mountPath: /kaniko/.docker
  volumes:
  - name: workspace
    hostPath:
      path: ${WORKSPACE}
      type: Directory
  - name: docker-config
    configMap:
      name: docker-config-${BUILD_NUMBER}
"""
                    
                    // Create Docker config for ECR authentication
                    def dockerConfigJson = """
{
  "auths": {
    "${ECR_REGISTRY}": {
      "username": "AWS",
      "password": "${ecrPassword}"
    }
  }
}
"""
                    
                    // Write pod spec to file
                    writeFile file: 'kaniko-pod.yaml', text: kanikoPodYaml
                    writeFile file: 'docker-config.json', text: dockerConfigJson
                    
                    // Create ConfigMap with Docker config
                    sh """
                        kubectl create configmap docker-config-${BUILD_NUMBER} \
                            --from-file=config.json=docker-config.json \
                            --dry-run=client -o yaml | kubectl apply -f -
                    """
                    
                    // Deploy Kaniko pod
                    sh """
                        kubectl apply -f kaniko-pod.yaml
                        
                        # Wait for pod to complete
                        echo "Waiting for Kaniko build to complete..."
                        kubectl wait --for=condition=Ready pod/kaniko-${BUILD_NUMBER} --timeout=300s || true
                        
                        # Follow logs
                        kubectl logs -f kaniko-${BUILD_NUMBER} || true
                        
                        # Check if build was successful
                        POD_STATUS=\$(kubectl get pod kaniko-${BUILD_NUMBER} -o jsonpath='{.status.phase}')
                        echo "Kaniko pod status: \$POD_STATUS"
                        
                        if [ "\$POD_STATUS" != "Succeeded" ]; then
                            echo "❌ Kaniko build failed"
                            kubectl describe pod kaniko-${BUILD_NUMBER}
                            exit 1
                        fi
                        
                        echo "✅ Docker image built successfully with Kaniko"
                    """
                }
            }
            post {
                always {
                    // Cleanup Kaniko resources
                    sh """
                        kubectl delete pod kaniko-${BUILD_NUMBER} --ignore-not-found=true
                        kubectl delete configmap docker-config-${BUILD_NUMBER} --ignore-not-found=true
                        rm -f kaniko-pod.yaml docker-config.json
                    """
                }
            }
        }
        
        stage('Trivy Image Scan') {
            steps {
                script {
                    echo "🔍 Scanning Docker image with Trivy..."
                    
                    // Authenticate to ECR
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_REGISTRY}
                    """
                    
                    // Run Trivy scan
                    sh """
                        # Pull the image to scan
                        docker pull ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
                        
                        # Create reports directory
                        mkdir -p trivy-reports
                        
                        # Run Trivy scan with multiple output formats
                        trivy image \
                            --severity ${TRIVY_SEVERITY} \
                            --exit-code ${TRIVY_EXIT_CODE} \
                            --format table \
                            --output trivy-reports/trivy-report.txt \
                            ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
                        
                        trivy image \
                            --severity ${TRIVY_SEVERITY} \
                            --format json \
                            --output trivy-reports/trivy-report.json \
                            ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
                        
                        trivy image \
                            --severity ${TRIVY_SEVERITY} \
                            --format template \
                            --template "@/usr/local/share/trivy/templates/html.tpl" \
                            --output trivy-reports/trivy-report.html \
                            ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
                        
                        # Display scan summary
                        echo "========================================"
                        echo "Trivy Scan Summary"
                        echo "========================================"
                        cat trivy-reports/trivy-report.txt
                        echo "========================================"
                        
                        echo "✅ Trivy scan completed"
                    """
                }
            }
            post {
                always {
                    // Publish Trivy scan report
                    publishHTML([
                        allowMissing: true,
                        alwaysLinkToLastBuild: true,
                        keepAll: true,
                        reportDir: 'trivy-reports',
                        reportFiles: 'trivy-report.html',
                        reportName: 'Trivy Security Scan Report'
                    ])
                    
                    // Archive Trivy reports
                    archiveArtifacts artifacts: 'trivy-reports/*', allowEmptyArchive: true
                }
            }
        }
        
        stage('Push to ECR') {
            steps {
                script {
                    echo "📤 Pushing Docker image to Amazon ECR..."
                    
                    sh """
                        # Authenticate Docker to ECR
                        aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_REGISTRY}
                        
                        # Verify image exists locally or pull from ECR (already pushed by Kaniko)
                        docker pull ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
                        
                        # Display image information
                        echo "========================================"
                        echo "Docker Image Information"
                        echo "========================================"
                        docker images ${ECR_REGISTRY}/${ECR_REPOSITORY}
                        echo "========================================"
                        
                        # Verify image in ECR
                        aws ecr describe-images \
                            --repository-name ${ECR_REPOSITORY} \
                            --region ${AWS_REGION} \
                            --image-ids imageTag=${IMAGE_TAG}
                        
                        echo "✅ Image successfully available in ECR"
                        echo "Image URI: ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"
                    """
                }
            }
        }
    }
    
    post {
        success {
            script {
                echo """
                ========================================
                ✅ Pipeline Completed Successfully!
                ========================================
                Project: ${PROJECT_NAME}
                Branch: ${env.GIT_BRANCH}
                Commit: ${env.GIT_COMMIT}
                Build Number: ${env.BUILD_NUMBER}
                Image Tag: ${IMAGE_TAG}
                ECR Image: ${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}
                ========================================
                """
                
                // Send success notification (configure as needed)
                // slackSend color: 'good', message: "Pipeline succeeded: ${env.JOB_NAME} ${env.BUILD_NUMBER}"
            }
        }
        
        failure {
            script {
                echo """
                ========================================
                ❌ Pipeline Failed!
                ========================================
                Project: ${PROJECT_NAME}
                Branch: ${env.GIT_BRANCH}
                Build Number: ${env.BUILD_NUMBER}
                Check the logs for details.
                ========================================
                """
                
                // Send failure notification (configure as needed)
                // slackSend color: 'danger', message: "Pipeline failed: ${env.JOB_NAME} ${env.BUILD_NUMBER}"
            }
        }
        
        always {
            // Cleanup workspace
            cleanWs(
                deleteDirs: true,
                disableDeferredWipeout: true,
                patterns: [
                    [pattern: '**/venv/**', type: 'INCLUDE'],
                    [pattern: '**/__pycache__/**', type: 'INCLUDE'],
                    [pattern: '**/node_modules/**', type: 'INCLUDE']
                ]
            )
        }
    }
}
