pipeline {
  agent any

  environment {
    PROJECT_NAME = 'gig-router-backend'
    BACKEND_DIR = 'backend'

    AWS_REGION = 'us-east-1'
    AWS_ACCOUNT_ID = '517757113300'
    ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    ECR_REPO = 'backend-app'

    SHORT_COMMIT = sh(returnStdout: true, script: "git rev-parse --short HEAD").trim()
    IMAGE_TAG = "${BUILD_NUMBER}-${SHORT_COMMIT}"

    DB_NAME = 'testdb'
    DB_USER = 'test'
    DB_PASS = 'test'
    DB_HOST = 'localhost'  // Use Docker container hostname
    DB_PORT = '5432'
  }

  stages {

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Start Postgres for CI') {
      steps {
        sh '''
        docker rm -f test-db || true

        docker run -d \
          --name test-db \
          -e POSTGRES_DB=${DB_NAME} \
          -e POSTGRES_USER=${DB_USER} \
          -e POSTGRES_PASSWORD=${DB_PASS} \
          -p 5432:5432 \
          postgres:15

        echo "Waiting for Postgres to be ready..."
        for i in {1..30}; do
          docker exec test-db pg_isready -U ${DB_USER} && break
          sleep 2
        done
        '''
      }
    }

    stage('Setup Python') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          python3 -m venv venv
          . venv/bin/activate
          pip install --upgrade pip
          pip install -r requirements.txt
          pip install pytest pytest-cov
          '''
        }
      }
    }

    stage('Prepare Django') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          . venv/bin/activate

          export DB_NAME=${DB_NAME}
          export DB_USER=${DB_USER}
          export DB_PASSWORD=${DB_PASS}
          export DB_HOST=${DB_HOST}
          export DB_PORT=${DB_PORT}

          python manage.py collectstatic --noinput || true
          '''
        }
      }
    }

    stage('Run Tests + Migrations') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          . venv/bin/activate

          export DB_NAME=${DB_NAME}
          export DB_USER=${DB_USER}
          export DB_PASSWORD=${DB_PASS}
          export DB_HOST=${DB_HOST}
          export DB_PORT=${DB_PORT}

          echo "Applying migrations to Postgres..."
          python manage.py migrate --noinput

          echo "Running tests..."
          pytest --ds=gig_router.settings --cov=. --cov-report=xml
          '''
        }
      }
    }

    stage('SonarQube Analysis') {
      steps {
        dir("${BACKEND_DIR}") {
          withSonarQubeEnv('SonarQube') {
            sh '''
            sonar-scanner \
              -Dsonar.projectKey=gig-router-backend \
              -Dsonar.sources=. \
              -Dsonar.python.coverage.reportPaths=coverage.xml
            '''
          }
        }
      }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Kaniko Build (local)') {
      steps {
        sh '''
        docker run --rm \
          -v $(pwd)/${BACKEND_DIR}:/workspace \
          gcr.io/kaniko-project/executor \
          --context=/workspace \
          --dockerfile=/workspace/Dockerfile \
          --destination=${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG} \
          --destination=${ECR_REGISTRY}/${ECR_REPO}:latest \
          --no-push
        '''
      }
    }

    stage('Trivy Security Scan') {
      steps {
        sh '''
        trivy image \
          --severity HIGH,CRITICAL \
          --exit-code 1 \
          ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
        '''
      }
    }

    stage('Push to ECR') {
      steps {
        sh '''
        aws ecr get-login-password --region ${AWS_REGION} | \
          docker login --username AWS --password-stdin ${ECR_REGISTRY}

        docker push ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
        docker push ${ECR_REGISTRY}/${ECR_REPO}:latest
        '''
      }
    }
  }

  post {
    always {
      sh 'docker rm -f test-db || true'
      cleanWs()
    }

    success {
      echo "✅ CI completed — Image pushed: ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
    }

    failure {
      echo "❌ CI failed"
    }
  }
}

