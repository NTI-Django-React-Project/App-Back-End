pipeline {
  agent any

  environment {
    PROJECT_NAME = 'gig-router-backend'
    BACKEND_DIR = 'backend'

    // AWS_REGION = 'us-east-1'
    AWS_REGION = 'eu-north-1'
    // AWS_ACCOUNT_ID = '517757113300'
	  
	AWS_ACCOUNT_ID = '231056963705'
    ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
    // ECR_REPO = 'backend-app'
    ECR_REPO = 'gig-route-backend'

    SHORT_COMMIT = sh(returnStdout: true, script: "git rev-parse --short HEAD").trim()
    IMAGE_TAG = "${BUILD_NUMBER}-${SHORT_COMMIT}"

    DB_NAME = 'testdb'
    DB_USER = 'test'
    DB_PASS = 'test'
    DB_HOST = 'localhost'
    DB_PORT = '5432'
	DB_SSLMODE = 'disable' 
  }

  stages {

    stage('Checkout') {
      steps {
        echo "Checking out source code..."
        checkout scm
      }
    }

    stage('Start Real DB for Tests') {
      steps {
        sh '''
        echo "Removing any existing database container..."
        docker rm -f test-db || true

        echo "Starting PostgreSQL Docker container for testing..."
        docker run -d \
          --name test-db \
          -e POSTGRES_DB=${DB_NAME} \
          -e POSTGRES_USER=${DB_USER} \
          -e POSTGRES_PASSWORD=${DB_PASS} \
          -p 5432:5432 \
          postgres:15

        echo "Waiting for PostgreSQL to be ready..."
        for i in {1..30}; do
            if docker exec test-db pg_isready -U ${DB_USER} > /dev/null 2>&1; then
              echo "PostgreSQL is ready!"
              break
            fi
            echo "Waiting for PostgreSQL... attempt $i/30"
            sleep 2
        done

        echo "Final check..."
        docker exec test-db pg_isready -U ${DB_USER}
        '''
      }
    }

    stage('Setup Python') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          echo "Setting up Python virtual environment and dependencies..."
          python3 -m venv venv
          . venv/bin/activate
          pip install --upgrade pip
          pip install -r requirements.txt
          pip install pytest pytest-cov pytest-django
          '''
        }
      }
    }

    stage('Validate Database Connection') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          echo "Testing database connection..."
          . venv/bin/activate

          python << END
import psycopg2

try:
    conn = psycopg2.connect(
        dbname="${DB_NAME}",
        user="${DB_USER}",
        password="${DB_PASS}",
        host="${DB_HOST}",
        port="${DB_PORT}"
    )
    print("Successfully connected to the database!")
    conn.close()
except psycopg2.OperationalError as e:
    print("Failed to connect to database:", str(e))
    exit(1)
END
          '''
        }
      }
    }

    stage('Check Migration Folders') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          echo "Checking for migration folders in each app..."
          for app in users gigs venues ai_services notifications; do
            echo "=== $app ==="
            if [ -d "$app/migrations" ]; then
              echo "  ✓ migrations folder exists"
              ls -la $app/migrations/
            else
              echo "  ✗ NO migrations folder - creating..."
              mkdir -p $app/migrations
              touch $app/migrations/__init__.py
            fi
          done
          '''
        }
      }
    }

    stage('Create Missing Migrations') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          echo "Creating any missing migrations..."
          . venv/bin/activate

          export DB_NAME=${DB_NAME}
          export DB_USER=${DB_USER}
          export DB_PASSWORD=${DB_PASS}
          export DB_HOST=${DB_HOST}
          export DB_PORT=${DB_PORT}
		  echo "DB_SSLMODE=$DB_SSLMODE"

          echo "Running makemigrations for all apps..."
          python manage.py makemigrations

          echo "Checking migration status..."
          python manage.py showmigrations

          echo "Listing all migration files..."
          find . -path "*/migrations/*.py" -not -name "__init__.py"
          '''
        }
      }
    }

    stage('Build Django') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          echo "Setting Django static assets..."
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

    stage('Run All Tests') {
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
          echo "Running all tests with coverage..."
          . venv/bin/activate

          export DB_NAME=${DB_NAME}
          export DB_USER=${DB_USER}
          export DB_PASSWORD=${DB_PASS}
          export DB_HOST=${DB_HOST}
          export DB_PORT=${DB_PORT}

          echo "Collecting tests..."
          pytest --collect-only --quiet

          echo "Running tests with fresh database..."
          pytest --ds=gig_router.settings \
                 --create-db \
                 --disable-warnings \
                 --verbose \
                 --cov=. \
                 --cov-report=term-missing \
                 --cov-report=html \
                 --cov-report=xml
          '''
        }
      }
    }

    stage('SonarQube Analysis') {
      steps {
        dir("${BACKEND_DIR}") {
          withSonarQubeEnv('sonarqube') {
            sh """
              ${tool 'sonar-scanner'}/bin/sonar-scanner
            """
          }
        }
      }
    }
	  
	stage('SonarQube Quality Gate') {
      steps {
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('OWASP Dependency Check') {
      environment {
        NVD_API_KEY = credentials('NVD_API_KEY')
      }
      steps {
        dir("${BACKEND_DIR}") {
          sh '''
            mkdir -p owasp-report
		    docker run --rm \
			  --user root \
			  -v $(pwd):/src \
			  -v owasp-data:/usr/share/dependency-check/data \
			  owasp/dependency-check:latest \
			  --scan /src \
			  --format XML \
			  --out /src/owasp-report \
			  --nvdApiKey $NVD_API_KEY
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: "${BACKEND_DIR}/owasp-report/**", fingerprint: true
        }
      }
    }

	  
    stage('Kaniko Build (to tar)') {
      steps {
        sh '''
        echo "Building Docker image with Kaniko (saving to tar)..."
        docker run --rm \
          -v $(pwd)/${BACKEND_DIR}:/workspace \
          -v $(pwd)/kaniko-cache:/cache \
          gcr.io/kaniko-project/executor:latest \
          --context=/workspace \
          --dockerfile=/workspace/Dockerfile \
          --tarPath=/workspace/${ECR_REPO}.tar \
	  --cache-dir=/cache \
          --no-push

        echo "Docker image saved to ${ECR_REPO}.tar"
        '''
      }
    }

    stage('Load Image for Trivy Scan') {
      steps {
        sh '''
        echo "Loading Docker image from tar for Trivy scan..."
        docker load -i ${BACKEND_DIR}/${ECR_REPO}.tar

        echo "Tagging image with ECR name..."
        docker tag unset-repo/unset-image-name:latest \
          ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}

        docker tag unset-repo/unset-image-name:latest \
          ${ECR_REGISTRY}/${ECR_REPO}:latest
        '''
      }
    }


    stage('Trivy Security Scan') {
      steps {
        sh """
        echo "Scanning Docker image for vulnerabilities..."
        docker run --rm \
          -v /var/run/docker.sock:/var/run/docker.sock \
		  -v trivy-cache:/root/.cache/trivy \
          aquasec/trivy:latest image \
	  --scanners vuln \
          --severity HIGH,CRITICAL \
		  --timeout 15m \
		  --skip-db-update \
          --exit-code 0 \
          ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
        echo "Security scan passed"
        """
      }
    }

    // stage('Push to ECR') {
    //   steps {
    //     withCredentials([[
    //       $class: 'AmazonWebServicesCredentialsBinding',
    //       credentialsId: 'aws-ecr-creds'
    //     ]]) {
    //       sh '''
    //       echo "Logging into ECR..."
    //       aws ecr get-login-password --region ${AWS_REGION} | \
    //         docker login --username AWS --password-stdin ${ECR_REGISTRY}

    //       echo "Pushing Docker images..."
    //       docker tag ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
    //       docker push ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
    //       docker push ${ECR_REGISTRY}/${ECR_REPO}:latest
    //       echo "Image pushed successfully"
    //       '''
    //     }
    //   }
    // }

	stage('Push to ECR') {
	  steps {
	    sh """
	    echo "Logging into ECR..."
	    aws ecr get-login-password --region ${AWS_REGION} | \
	      docker login --username AWS --password-stdin ${ECR_REGISTRY}
	    echo "Pushing Docker images..."
        docker tag ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
	    docker push ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
	    docker push ${ECR_REGISTRY}/${ECR_REPO}:latest

	    """
	  }
	}

	// stage('Update Kubernetes Manifest') {


	  		// echo "Pushing Docker images..."
     //    docker tag ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
	    // docker push ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
	    // docker push ${ECR_REGISTRY}/${ECR_REPO}:latest

	    // docker tag ${ECR_REPO}:${IMAGE_TAG} \
     //             ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
     //  docker tag ${ECR_REPO}:${IMAGE_TAG} \
     //             ${ECR_REGISTRY}/${ECR_REPO}:latest
     //  echo "Pushing images..."
     //  docker push ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
     //  docker push ${ECR_REGISTRY}/${ECR_REPO}:latest
 //      steps {
 //        withCredentials([usernamePassword(
 //          credentialsId: 'github-creds',
 //          usernameVariable: 'moessam634',
 //          passwordVariable: 'GIT_PASSWORD'
 //        )]) {
 //          sh '''
 //          echo "Cloning GitOps repository..."
 //          rm -rf gitops-repo
 //          git clone https://${GIT_USERNAME}:${GIT_PASSWORD}@github.com/YOUR-ORG/k8s-manifests.git gitops-repo
 //          cd gitops-repo
          
 //          git config user.name "Jenkins CI"
 //          git config user.email "jenkins@yourdomain.com"
          
 //          git checkout ${GITOPS_BRANCH}
          
 //          echo "Updating image tag in deployment manifest..."
 //          sed -i "s|image: ${ECR_REGISTRY}/${ECR_REPO}:.*|image: ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}|g" ${MANIFEST_PATH}
          
 //          echo "Committing and pushing changes..."
 //          git add ${MANIFEST_PATH}
 //          git commit -m "Update backend image to ${IMAGE_TAG} - Build #${BUILD_NUMBER}" || echo "No changes to commit"
 //          git push origin ${GITOPS_BRANCH}
          
 //          echo "Manifest updated successfully!"
 //          cd ..
 //          rm -rf gitops-repo
 //          '''
 //        }
 //      }
 //    }

	// stage('Update K8s Deployment') {
	//   when {
	//     branch 'main'  // Only update on main branch
	//   }
	//   steps {
	//     withCredentials([usernamePassword(
	//       credentialsId: 'github-creds',
	//       usernameVariable: 'GIT_USERNAME',
	//       passwordVariable: 'GIT_TOKEN'
	//     )]) {
	//       sh '''
	//         echo "Cloning K8s config repository..."
	//         rm -rf k8s-config
	//         git clone https://${GIT_TOKEN}@github.com/yourorg/k8s-config.git
	//         cd k8s-config
	        
	//         DEPLOYMENT_FILE="apps/gig-router-backend/deployment.yaml"
	//         NEW_IMAGE="${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
	        
	//         echo "Updating deployment image to: ${NEW_IMAGE}"
	//         sed -i "s|image:.*${ECR_REPO}.*|image: ${NEW_IMAGE}|g" ${DEPLOYMENT_FILE}
	        
	//         git config user.email "ci@gig-router.com"
	//         git config user.name "Jenkins CI Bot"
	//         git add ${DEPLOYMENT_FILE}
	//         git diff --staged
	//         git commit -m "ci: update gig-router-backend to ${IMAGE_TAG}
	
	//         Build: ${BUILD_NUMBER}
	//         Commit: ${SHORT_COMMIT}"
	//         git push origin main
	        
	//         echo "✓ Deployment manifest updated successfully"
	//       '''
	//     }
	//   }
	// }


	  
	// stage('Update K8s Deployment') {
	//   when {
	//     branch 'main'
	//   }
	//   steps {
	//     withCredentials([string(credentialsId: 'github-creds', variable: 'GITHUB_TOKEN')]) {
	//       sh '''
	//         echo "Syncing with K8s manifests repository..."
	        
	//         # If already cloned, just update it
	//         if [ -d "k8s-manifests/.git" ]; then
	//           echo "Repository already exists, updating..."
	//           cd k8s-manifests
	//           git fetch origin main
	//           git reset --hard origin/main  # Force sync with GitHub
	//           git clean -fd  # Remove any local changes
	//           echo "✓ Synced with latest from GitHub"
	//         else
	//           echo "First time clone..."
	//           git clone https://${GITHUB_TOKEN}@github.com/NTI-Django-React-Project/k8s-manifests.git
	//           cd k8s-manifests
	//           echo "✓ Cloned from GitHub"
	//         fi
	        
	//         echo "All your manifests are here:"
	//         ls -la
	//         ls -la backend/
	        
	//         DEPLOYMENT_FILE="backend/deployment.yaml"
	//         NEW_IMAGE="${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
	        
	//         echo "Current image:"
	//         grep "image:" ${DEPLOYMENT_FILE}
	        
	//         echo "Updating to: ${NEW_IMAGE}"
	//         sed -i "s|image:.*backend.*|image: ${NEW_IMAGE}|g" ${DEPLOYMENT_FILE}
	        
	//         echo "New image:"
	//         grep "image:" ${DEPLOYMENT_FILE}
	        
	//         git config user.email "jenkins-ci@nti-project.com"
	//         git config user.name "Jenkins CI Bot"
	//         git add ${DEPLOYMENT_FILE}
	//         git commit -m "ci: update backend to ${IMAGE_TAG} [Build: ${BUILD_NUMBER}]"
	//         git push https://${GITHUB_TOKEN}@github.com/NTI-Django-React-Project/k8s-manifests.git main
	        
	//         echo "✓ Deployment updated successfully!"
	//       '''
	//     }
	//   }
	// }
  } // stages

  post {
    always {
      echo "Cleaning up resources..."
      sh 'docker rm -f test-db || true'

      script {
        try {
          publishHTML([
            allowMissing: true,
            alwaysLinkToLastBuild: true,
            keepAll: true,
            reportDir: 'backend/htmlcov',
            reportFiles: 'index.html',
            reportName: 'Coverage Report'
          ])
        } catch (Exception e) {
          echo "Could not publish coverage report: ${e.message}"
        }
      }

      cleanWs()
    }

    success {
      echo "CI pipeline completed successfully!"
      echo "Image pushed: ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
    }

    failure {
      echo "CI pipeline failed. Check the logs for details."
    }
  }
}

