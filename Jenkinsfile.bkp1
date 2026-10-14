
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        skipDefaultCheckout(true)
    }

    environment {
        DEPLOY_HOST    = '192.168.1.32'
        DEPLOY_USER    = 'deploy'
        APP_DIR        = '/opt/flask-app'
        IMAGE_NAME     = 'flask-demo'
        CONTAINER_NAME = 'flask-demo'
        APP_PORT       = '8080'
        CONTAINER_PORT = '5000'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    set -eu
                    test -f app.py
                    test -f Dockerfile
                    test -f requirements.txt
                    test -d templates

                    echo "Application files verified."
                '''
            }
        }

        stage('Validate SSH and Docker') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh -o StrictHostKeyChecking=accept-new \
                            ${DEPLOY_USER}@${DEPLOY_HOST} '
                                set -eu
                                docker --version
                                docker info >/dev/null
                                echo "SSH and Docker are ready."
                            '
                    '''
                }
            }
        }

        stage('Prepare Remote Directory') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh ${DEPLOY_USER}@${DEPLOY_HOST} \
                            "mkdir -p ${APP_DIR}"
                    '''
                }
            }
        }

        stage('Copy Application') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        scp app.py Dockerfile requirements.txt \
                            ${DEPLOY_USER}@${DEPLOY_HOST}:${APP_DIR}/

                        scp -r templates \
                            ${DEPLOY_USER}@${DEPLOY_HOST}:${APP_DIR}/
                    '''
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh ${DEPLOY_USER}@${DEPLOY_HOST} "
                            set -eu
                            cd ${APP_DIR}

                            docker build \
                                -t ${IMAGE_NAME}:${BUILD_NUMBER} .

                            docker image inspect \
                                ${IMAGE_NAME}:${BUILD_NUMBER} >/dev/null

                            echo 'Docker image built successfully.'
                        "
                    '''
                }
            }
        }

        stage('Deploy Container') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh ${DEPLOY_USER}@${DEPLOY_HOST} "
                            set -eu

                            if docker container inspect \
                                ${CONTAINER_NAME} >/dev/null 2>&1; then
                                docker rm -f ${CONTAINER_NAME}
                            fi

                            docker run -d \
                                --name ${CONTAINER_NAME} \
                                --restart unless-stopped \
                                -p ${APP_PORT}:${CONTAINER_PORT} \
                                ${IMAGE_NAME}:${BUILD_NUMBER}

                            docker ps --filter \
                                name=^/${CONTAINER_NAME}$

                            echo 'Container deployed successfully.'
                        "
                    '''
                }
            }
        }

        stage('Health Check') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        set -eu

                        ssh ${DEPLOY_USER}@${DEPLOY_HOST} \
                            "APP_PORT=${APP_PORT} CONTAINER_NAME=${CONTAINER_NAME} bash -s" <<'REMOTE_SCRIPT'
set -eu

attempt=1
max_attempts=12

while [ "$attempt" -le "$max_attempts" ]; do
    if curl -fsS "http://localhost:${APP_PORT}/health"; then
        echo
        echo "Health check successful."
        exit 0
    fi

    echo "Attempt $attempt failed; retrying..."
    attempt=$((attempt + 1))
    sleep 5
done

echo "Health check failed."
docker logs --tail 100 "$CONTAINER_NAME"
exit 1
REMOTE_SCRIPT
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'Flask deployment successful.'
            echo 'Application URL: http://192.168.1.32:8080'
        }

        failure {
            echo 'Pipeline failed. Check the failed stage in Console Output.'
        }

        always {
            echo 'Jenkins pipeline execution completed.'
        }
    }
}
