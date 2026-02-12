# Gig Router Backend - Jenkins CI/CD Pipeline


A comprehensive Jenkins pipeline for building, testing, securing, and deploying the Gig Router Backend Django application to AWS ECR.

## 📋 Table of Contents

- [Overview](#overview)
- [Pipeline Architecture](#pipeline-architecture)
- [Prerequisites](#prerequisites)
- [Environment Variables](#environment-variables)
- [Pipeline Stages](#pipeline-stages)
- [Security & Quality Gates](#security--quality-gates)
- [Notifications](#notifications)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

## 🎯 Overview

This Jenkins pipeline automates the complete CI/CD workflow for the Gig Router Backend application, including:

- Automated testing with real PostgreSQL database
- Code quality analysis with SonarQube
- Security scanning with OWASP Dependency Check and Trivy
- Docker image building with Kaniko
- Package management with Nexus Repository
- Container registry management with AWS ECR
- Webhook notifications for build status

## 🏗️ Pipeline Architecture

```
┌─────────────┐
│  Checkout   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Start DB   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Setup Python│
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Validate   │
│  Database   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Migrations  │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    Tests    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  SonarQube  │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    OWASP    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    Nexus    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│   Kaniko    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│    Trivy    │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│  Push ECR   │
└─────────────┘
```

## 📦 Prerequisites

### Jenkins Plugins Required

- Pipeline Plugin
- Docker Pipeline Plugin
- Git Plugin
- SonarQube Scanner Plugin
- HTML Publisher Plugin
- Credentials Binding Plugin
- AWS Steps Plugin

### External Services

1. **PostgreSQL** (via Docker)
   - Image: `postgres:15`
   - Required for integration testing

2. **SonarQube Server**
   - Configured as 'sonarqube' in Jenkins
   - Requires sonar-scanner tool installation

3. **Nexus Repository Manager**
   - Hosted at: `http://51.20.143.84:8081`
   - Repository: `python-backend-app`

4. **AWS ECR**
   - Region: `eu-north-1`
   - Account ID: `231056963705`
   - Repository: `gig-route-backend`

5. **Webhook Endpoint**
   - URL: `http://174.129.167.238:5678/webhook/essam`
   - For build notifications

### Jenkins Credentials Required

| Credential ID | Type | Description |
|--------------|------|-------------|
| `NVD_API_KEY` | Secret Text | National Vulnerability Database API Key |
| `nexus-cred` | Username/Password | Nexus repository credentials |
| AWS Credentials | AWS | ECR authentication (via AWS CLI) |

### Tools Configuration

- **Python**: 3.x with pip
- **Docker**: Latest version with BuildKit support
- **AWS CLI**: Configured with ECR access
- **Sonar Scanner**: Configured in Jenkins tools

## 🔧 Environment Variables

### Project Configuration

```groovy
PROJECT_NAME = 'gig-router-backend'
BACKEND_DIR = 'backend'
```

### AWS Configuration

```groovy
AWS_REGION = 'eu-north-1'
AWS_ACCOUNT_ID = '231056963705'
ECR_REGISTRY = '231056963705.dkr.ecr.eu-north-1.amazonaws.com'
ECR_REPO = 'gig-route-backend'
```

### Image Tagging

```groovy
SHORT_COMMIT = git rev-parse --short HEAD
IMAGE_TAG = "${BUILD_NUMBER}-${SHORT_COMMIT}"
```

Example: `42-a3f5c21`

### Database Configuration

```groovy
DB_NAME = 'testdb'
DB_USER = 'test'
DB_PASS = 'test'
DB_HOST = 'localhost'
DB_PORT = '5432'
DB_SSLMODE = 'disable'
```

## 🔄 Pipeline Stages

### 1. Checkout
**Purpose**: Clone the source code repository

```groovy
checkout scm
```

### 2. Start Real DB for Tests
**Purpose**: Launch PostgreSQL container for integration testing

**Actions**:
- Removes existing test-db container
- Starts PostgreSQL 15 container
- Waits up to 60 seconds for database readiness
- Validates connection with `pg_isready`

**Container Details**:
```bash
docker run -d \
  --name test-db \
  -e POSTGRES_DB=testdb \
  -e POSTGRES_USER=test \
  -e POSTGRES_PASSWORD=test \
  -p 5432:5432 \
  postgres:15
```

### 3. Setup Python
**Purpose**: Configure Python environment and dependencies

**Actions**:
- Creates Python virtual environment
- Upgrades pip
- Installs project dependencies from `requirements.txt`
- Installs testing packages: pytest, pytest-cov, pytest-django

### 4. Validate Database Connection
**Purpose**: Verify database connectivity before running migrations

**Test**:
```python
import psycopg2
conn = psycopg2.connect(dbname, user, password, host, port)
```

### 5. Check Migration Folders
**Purpose**: Ensure migration directories exist for all Django apps

**Apps Checked**:
- users
- gigs
- venues
- ai_services
- notifications

**Actions**:
- Verifies `migrations/` folder exists
- Creates missing folders with `__init__.py`

### 6. Create Missing Migrations
**Purpose**: Generate Django database migrations

**Actions**:
```bash
python manage.py makemigrations
python manage.py showmigrations
```

### 7. Build Django
**Purpose**: Collect static assets

**Actions**:
```bash
python manage.py collectstatic --noinput
```

### 8. Run All Tests
**Purpose**: Execute test suite with coverage reporting

**Test Configuration**:
- Framework: pytest with Django settings
- Database: Fresh test database created per run
- Coverage formats: terminal, HTML, XML

**Command**:
```bash
pytest --ds=gig_router.settings \
       --create-db \
       --disable-warnings \
       --verbose \
       --cov=. \
       --cov-report=term-missing \
       --cov-report=html \
       --cov-report=xml
```

**Coverage Reports**:
- Terminal output with missing lines
- HTML report in `backend/htmlcov/`
- XML report for SonarQube integration

### 9. SonarQube Analysis
**Purpose**: Static code analysis and quality metrics

**Integration**:
- Uses configured SonarQube server
- Requires `sonar-project.properties` in backend directory
- Analyzes code quality, bugs, vulnerabilities, code smells

### 10. SonarQube Quality Gate
**Purpose**: Enforce code quality standards

**Configuration**:
- Timeout: 5 minutes
- Behavior: Aborts pipeline on failure
- Validates against quality gate thresholds

### 11. OWASP Dependency Check
**Purpose**: Scan dependencies for known vulnerabilities

**Configuration**:
```bash
docker run --rm \
  --user root \
  -v $(pwd):/src \
  -v owasp-data:/usr/share/dependency-check/data \
  owasp/dependency-check:latest \
  --scan /src \
  --format XML \
  --out /src/owasp-report \
  --nvdApiKey $NVD_API_KEY
```

**Outputs**:
- XML report in `backend/owasp-report/`
- Archived as build artifact

### 12. Build & Upload Python Package to Nexus
**Purpose**: Package and publish Python distribution

**Actions**:
1. Configure `.pypirc` with Nexus credentials
2. Build source distribution and wheel
3. Upload to Nexus repository

**Commands**:
```bash
python setup.py sdist bdist_wheel
twine upload --repository nexus dist/*
```

### 13. Kaniko Build (to tar)
**Purpose**: Build Docker image without Docker daemon

**Why Kaniko?**
- Secure: No privileged Docker daemon access required
- Cacheable: Efficient layer caching
- Reproducible: Consistent builds

**Configuration**:
```bash
docker run --rm \
  -v $(pwd)/backend:/workspace \
  -v $(pwd)/kaniko-cache:/cache \
  gcr.io/kaniko-project/executor:latest \
  --context=/workspace \
  --dockerfile=/workspace/Dockerfile \
  --tarPath=/workspace/gig-route-backend.tar \
  --cache-dir=/cache \
  --no-push
```

**Output**: Docker image saved as `.tar` file

### 14. Load Image for Trivy Scan
**Purpose**: Prepare image for security scanning

**Actions**:
```bash
docker load -i backend/gig-route-backend.tar
docker tag unset-repo/unset-image-name:latest \
  231056963705.dkr.ecr.eu-north-1.amazonaws.com/gig-route-backend:${IMAGE_TAG}
```

### 15. Trivy Security Scan
**Purpose**: Vulnerability scanning of Docker image

**Configuration**:
- Scanners: Vulnerabilities only
- Severity: HIGH, CRITICAL
- Timeout: 15 minutes
- Exit code: 0 (report only, doesn't fail build)

**Command**:
```bash
trivy image \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --timeout 15m \
  --skip-db-update \
  --exit-code 0 \
  ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
```

### 16. Push to ECR
**Purpose**: Upload Docker images to AWS Elastic Container Registry

**Actions**:
1. Authenticate with ECR using AWS CLI
2. Push versioned image tag
3. Push latest tag

**Tags Pushed**:
- `${BUILD_NUMBER}-${SHORT_COMMIT}` (e.g., `42-a3f5c21`)
- `latest`

## 🔒 Security & Quality Gates

### Code Quality (SonarQube)
- **Stage**: SonarQube Quality Gate
- **Action**: Aborts pipeline on quality gate failure
- **Timeout**: 5 minutes

### Dependency Vulnerabilities (OWASP)
- **Stage**: OWASP Dependency Check
- **Action**: Reports vulnerabilities, archived for review
- **Database**: National Vulnerability Database (NVD)

### Container Security (Trivy)
- **Stage**: Trivy Security Scan
- **Focus**: HIGH and CRITICAL vulnerabilities
- **Action**: Reports but doesn't block (exit-code 0)

### Test Coverage
- **Minimum**: Defined in pytest configuration
- **Reports**: HTML and XML formats
- **Published**: Via HTML Publisher Plugin

## 📬 Notifications

### Webhook Integration

The pipeline sends build notifications to a webhook endpoint with detailed status information.

**Endpoint**: `http://174.129.167.238:5678/webhook/essam`

### Success Notification

```json
{
  "status": "SUCCESS",
  "job": "${JOB_NAME}",
  "build": "${BUILD_NUMBER}",
  "image": "231056963705.dkr.ecr.eu-north-1.amazonaws.com/gig-route-backend",
  "tag": "${IMAGE_TAG}",
  "url": "${BUILD_URL}"
}
```

### Failure Notification

```json
{
  "status": "FAILED",
  "job": "${JOB_NAME}",
  "build": "${BUILD_NUMBER}",
  "image": "231056963705.dkr.ecr.eu-north-1.amazonaws.com/gig-route-backend",
  "tag": "${IMAGE_TAG}",
  "url": "${BUILD_URL}"
}
```

## 🛠️ Troubleshooting

### Database Connection Issues

**Problem**: Tests fail due to database connection
**Solution**:
1. Check if PostgreSQL container is running: `docker ps | grep test-db`
2. Verify port 5432 is not in use: `lsof -i :5432`
3. Check container logs: `docker logs test-db`

### SonarQube Quality Gate Failures

**Problem**: Pipeline aborts at quality gate
**Solution**:
1. Review SonarQube dashboard for specific issues
2. Check for code smells, bugs, or security hotspots
3. Ensure code coverage meets minimum threshold

### Kaniko Build Failures

**Problem**: Docker image build fails
**Solution**:
1. Verify Dockerfile exists in backend directory
2. Check Kaniko cache volume has sufficient space
3. Review build logs for missing dependencies

### ECR Push Failures

**Problem**: Unable to push to ECR
**Solution**:
1. Verify AWS credentials are configured: `aws sts get-caller-identity`
2. Check ECR repository exists: `aws ecr describe-repositories`
3. Ensure proper IAM permissions for ECR operations

### OWASP Scan Timeout

**Problem**: Dependency check takes too long
**Solution**:
1. Check NVD API key is valid
2. Verify network connectivity to NVD servers
3. Consider increasing timeout or using cached database

## 🔧 Maintenance

### Regular Tasks

#### Weekly
- Review OWASP dependency check reports
- Update vulnerable dependencies
- Monitor test coverage trends

#### Monthly
- Update base Docker images
- Review and clean old ECR images
- Update Jenkins plugins

#### Quarterly
- Rotate credentials (Nexus, NVD API key)
- Review and optimize pipeline performance
- Update Python dependencies

### Pipeline Optimization

**Cache Management**:
- Kaniko cache: `$(pwd)/kaniko-cache`
- Trivy cache: `trivy-cache` Docker volume
- OWASP data: `owasp-data` Docker volume

**Performance Tips**:
1. Use `--skip-db-update` for Trivy in frequent builds
2. Enable Kaniko caching for faster image builds
3. Run tests in parallel where possible
4. Archive only necessary artifacts

### Cleanup Scripts

**Remove old test containers**:
```bash
docker ps -a | grep test-db | awk '{print $1}' | xargs docker rm -f
```

**Clean old ECR images**:
```bash
aws ecr list-images --repository-name gig-route-backend \
  --filter tagStatus=UNTAGGED \
  --query 'imageIds[*]' --output json | \
  jq -r '.[] | .imageDigest' | \
  xargs -I {} aws ecr batch-delete-image \
    --repository-name gig-route-backend \
    --image-ids imageDigest={}
```

## 📊 Artifacts & Reports

### Published Artifacts

1. **Coverage Report**
   - Location: `backend/htmlcov/index.html`
   - Access: Via Jenkins HTML Publisher
   - Retention: All builds

2. **OWASP Report**
   - Location: `backend/owasp-report/`
   - Format: XML
   - Retention: Per build configuration

3. **Python Package**
   - Repository: Nexus `python-backend-app`
   - Format: Wheel (.whl) and Source Distribution (.tar.gz)

4. **Docker Images**
   - Registry: AWS ECR
   - Tags: `${BUILD_NUMBER}-${SHORT_COMMIT}`, `latest`

## 📝 Configuration Files

### Required Files in Repository

```
backend/
├── Dockerfile              # Container definition
├── requirements.txt        # Python dependencies
├── setup.py               # Package configuration
├── manage.py              # Django management
├── pytest.ini             # Test configuration
├── sonar-project.properties # SonarQube config
└── users/migrations/
    ├── gigs/migrations/
    ├── venues/migrations/
    ├── ai_services/migrations/
    └── notifications/migrations/
```

### Jenkins Configuration

**System Configuration**:
- SonarQube server: Named 'sonarqube'
- Sonar scanner tool: Named 'sonar-scanner'

**Global Credentials**:
- `NVD_API_KEY`: National Vulnerability Database API key
- `nexus-cred`: Nexus username/password
- AWS credentials for ECR access

## 🤝 Contributing

When modifying this pipeline:

1. Test changes in a development Jenkins instance
2. Validate all security scans still function
3. Update this README with any new stages or requirements
4. Ensure backward compatibility with existing builds
5. Document any new environment variables or credentials


---

**Last Updated**: February 2026  
**Pipeline Version**: 2.0  
**Maintained By**: DevOps Team
