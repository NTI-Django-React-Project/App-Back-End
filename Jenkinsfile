pipeline {
  agent any

  environment {
    IMAGE = "django-backend:${BUILD_NUMBER}"
  }

  stages {

    stage('Build') {
      steps {
        sh 'pip install -r requirements.txt'
      }
    }

    stage('Test with real DB') {
      steps {
        sh 'pytest'
      }
    }

    stage('SonarQube') {
      steps {
        withSonarQubeEnv('SonarQube') {
          sh 'sonar-scanner'
        }
      }
    }

    stage('Kaniko Build') {
      steps {
        sh '''
        docker run --rm \
          -v $(pwd):/workspace \
          gcr.io/kaniko-project/executor \
          --context=/workspace \
          --dockerfile=Dockerfile \
          --destination=${IMAGE} \
          --no-push
        '''
      }
    }

    stage('Trivy Scan') {
      steps {
        sh 'trivy image ${IMAGE}'
      }
    }
  }
}

