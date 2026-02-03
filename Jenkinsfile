pipeline {
    agent any
    
    environment {
        AWS_REGION = 'us-east-1'
        ECR_REGISTRY = credentials('backend-ecr-registry')
        IMAGE_NAME = 'backend-app'
        IMAGE_TAG = "${env.BUILD_NUMBER}"
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
                        pip list
                    '''
                }
            }
        }
        
        stage('Test') {
            steps {
                echo '=== Running Tests ==='
                dir('backend') {
                    sh '''
                        . venv/bin/activate
                        export DJANGO_SETTINGS_MODULE=gig_router.settings
                        export SECRET_KEY=test-secret-key-for-ci
                        export DEBUG=False
                        export DB_ENGINE=django.db.backends.sqlite3
                        export DB_NAME=:memory:
                        export ALLOWED_HOSTS=localhost,127.0.0.1
                        
                        # Run tests
                        pytest -v --junitxml=test-results/pytest-report.xml \
                               --cov=. --cov-report=xml --cov-report=html
                    '''
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
        
        stage('SonarQube Analysis') {
            steps {
                echo '=== Running SonarQube Analysis ==='
                dir('backend') {
                    script {
                        withSonarQubeEnv('SonarQube') {
                            sh '''
                                sonar-scanner
                            '''
                        }
                    }
                }
            }
        }
        
        stage('Quality Gate') {
            steps {
                echo '=== Waiting for Quality Gate ==='
                timeout(time: 5, unit: 'MINUTES') {
                    script {
                        def qg = waitForQualityGate()
                        if (qg.status != 'OK') {
                            error "Pipeline aborted due to quality gate failure: ${qg.status}"
                        }
                    }
                }
            }
        }
        
        stage('OWASP Dependency Check') {
            steps {
                echo '=== Running OWASP Dependency Check ==='
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
                echo '=== Building Docker Image ==='
                dir('backend') {
                    script {
                        sh """
                            docker build -t ${IMAGE_NAME}:${IMAGE_TAG} .
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${IMAGE_NAME}:latest
                            docker images | grep ${IMAGE_NAME}
                        """
                    }
                }
            }
        }
        
        stage('Trivy Image Scan') {
            steps {
                echo '=== Scanning Docker Image with Trivy ==='
                sh """
                    trivy image \
                        --severity HIGH,CRITICAL \
                        --format json \
                        --output trivy-report.json \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                    
                    # Show summary
                    trivy image \
                        --severity HIGH,CRITICAL \
                        ${IMAGE_NAME}:${IMAGE_TAG}
                """
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-report.json', allowEmptyArchive: true
                }
            }
        }
        
        stage('Push to ECR') {
            steps {
                echo '=== Pushing Image to AWS ECR ==='
                script {
                    withAWS(credentials: 'aws-credentials', region: "${AWS_REGION}") {
                        sh """
                            # Login to ECR
                            aws ecr get-login-password --region ${AWS_REGION} | \
                                docker login --username AWS --password-stdin ${ECR_REGISTRY}
                            
                            # Tag images
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${ECR_REGISTRY}/${IMAGE_NAME}:latest
                            
                            # Push to ECR
                            docker push ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}
                            docker push ${ECR_REGISTRY}/${IMAGE_NAME}:latest
                            
                            echo "✅ Image pushed successfully!"
                            echo "Image URI: ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
                        """
                    }
                }
            }
        }
    }
    
    post {
        always {
            echo '=== Cleaning up workspace ==='
            cleanWs()
        }
        success {
            echo '✅ Pipeline completed successfully!'
            echo "Docker image: ${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
        }
        failure {
            echo '❌ Pipeline failed!'
        }
    }
}
