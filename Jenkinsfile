pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    environment {
        DEPLOY_HOST  = '192.168.1.32'
        DEPLOY_USER  = 'deploy'
        APP_DIR      = '/opt/flask-app'

        DOCKERHUB_REPO = 'rohitkotla/flask-demo'
        CONTAINER_NAME = 'flask-demo'
        APP_PORT       = '8080'
        CONTAINER_PORT = '5000'

        SSH_CREDENTIALS = 'docker-server-ssh'
        DOCKERHUB_CREDENTIALS = 'docker-hub-creds'
    }

    stages {

        // 1. Checkout and validate project files
        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    set -eu

                    test -f app.py
                    test -f Dockerfile
                    test -f requirements.txt
                    test -f requirements-ci.txt
                    test -d templates
                    test -d tests

                    echo "Project files validated."
                '''
            }
        }

        // 2. Prepare Python environment on Jenkins agent
        stage('Setup CI Environment') {
            steps {
                sh '''
                    set -eu

                    python3 --version
                    python3 -m venv .venv-ci

                    .venv-ci/bin/python -m pip install \
                        --upgrade pip

                    .venv-ci/bin/python -m pip install \
                        -r requirements.txt \
                        -r requirements-ci.txt
                '''
            }
        }

        // 3. Run application tests
        stage('Unit Tests') {
            steps {
                sh '''
                    set -eu
                    .venv-ci/bin/python -m pytest -q
                '''
            }
        }

        // 4. Check code quality
        stage('Code Quality') {
            steps {
                sh '''
                    set -eu
                    .venv-ci/bin/ruff check app.py tests/
                '''
            }
        }

        // 5. Audit runtime Python dependencies
        stage('Dependency Security Audit') {
            steps {
                sh '''
                    set -eu
                    .venv-ci/bin/pip-audit -r requirements.txt
                '''
            }
        }

        // 6. Validate remote Docker and Trivy
        stage('Validate Deployment Server') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh -o BatchMode=yes \
                            -o StrictHostKeyChecking=yes \
                            "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "docker --version &&
                             trivy --version &&
                             docker info >/dev/null"
                    '''
                }
            }
        }

        // 7. Prepare remote application directory
        stage('Prepare Remote Directory') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "mkdir -p '${APP_DIR}'"
                    '''
                }
            }
        }

        // 8. Copy application files to Docker server
        stage('Copy Application Files') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        scp app.py Dockerfile requirements.txt \
                            "${DEPLOY_USER}@${DEPLOY_HOST}:${APP_DIR}/"

                        scp -r templates \
                            "${DEPLOY_USER}@${DEPLOY_HOST}:${APP_DIR}/"
                    '''
                }
            }
        }

        // 9. Build a uniquely tagged image on the remote server
        stage('Build Docker Image') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "cd '${APP_DIR}' &&
                             docker build --pull \
                               -t '${DOCKERHUB_REPO}:${BUILD_NUMBER}' \
                               -t '${DOCKERHUB_REPO}:latest' ."
                    '''
                }
            }
        }

        // 10. Generate a full HIGH/CRITICAL Trivy report
        stage('Trivy Vulnerability Report') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        IMAGE="${DOCKERHUB_REPO}:${BUILD_NUMBER}"
                        REPORT="trivy-report-${BUILD_NUMBER}.json"

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "trivy image \
                             --scanners vuln \
                             --severity HIGH,CRITICAL \
                             --format json \
                             --output '/tmp/${REPORT}' \
                             '${IMAGE}'"

                        scp "${DEPLOY_USER}@${DEPLOY_HOST}:/tmp/${REPORT}" \
                            "${REPORT}"
                    '''
                }
            }

            post {
                always {
                    archiveArtifacts(
                        artifacts: 'trivy-report-*.json',
                        allowEmptyArchive: true,
                        fingerprint: true
                    )
                }
            }
        }

        // 11. Fail if fixable HIGH/CRITICAL vulnerabilities exist
        stage('Trivy Security Gate') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        IMAGE="${DOCKERHUB_REPO}:${BUILD_NUMBER}"

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "trivy image \
                             --scanners vuln \
                             --ignore-unfixed \
                             --severity HIGH,CRITICAL \
                             --exit-code 1 \
                             '${IMAGE}'"

                        echo "Trivy security gate passed."
                    '''
                }
            }
        }

        // 12. Push image only after all previous checks pass
        stage('Push to Docker Hub') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'docker-hub-creds',
                            usernameVariable: 'DH_USER',
                            passwordVariable: 'DH_PASS'
                        )
                    ]) {
                        sh '''
                            set -eu

                            printf '%s' "$DH_PASS" |
                                ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                                "docker login \
                                 --username '${DH_USER}' \
                                 --password-stdin &&
                                 docker push '${DOCKERHUB_REPO}:${BUILD_NUMBER}' &&
                                 docker push '${DOCKERHUB_REPO}:latest' &&
                                 docker logout"
                        '''
                    }
                }
            }
        }

        // 13. Deploy the exact image that passed the scans
        stage('Deploy Application') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        IMAGE="${DOCKERHUB_REPO}:${BUILD_NUMBER}"

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "docker rm -f '${CONTAINER_NAME}' 2>/dev/null || true"

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" \
                            "docker run -d \
                             --name '${CONTAINER_NAME}' \
                             --restart unless-stopped \
                             -p '${APP_PORT}:${CONTAINER_PORT}' \
                             '${IMAGE}'"
                    '''
                }
            }
        }

        // 14. Verify application health on the Docker server
        stage('Health Check') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh "${DEPLOY_USER}@${DEPLOY_HOST}" '
                            for i in $(seq 1 12); do
                                if curl -fsS \
                                    http://127.0.0.1:8080/health; then
                                    echo
                                    echo "Health check passed."
                                    exit 0
                                fi

                                echo "Waiting for application... attempt $i/12"
                                sleep 5
                            done

                            echo "Health check failed."
                            docker logs --tail 100 flask-demo
                            exit 1
                        '
                    '''
                }
            }
        }
    }

    post {
        success {
            echo """
                CI/CD pipeline completed successfully.
                Image: ${DOCKERHUB_REPO}:${BUILD_NUMBER}
                Application: http://${DEPLOY_HOST}:${APP_PORT}
            """
        }

        failure {
            echo """
                CI/CD pipeline failed.
                Check the failed stage and Jenkins console output.
                The deployment may not have completed successfully.
            """
        }

        always {
            echo 'Pipeline execution finished.'
        }
    }
}
