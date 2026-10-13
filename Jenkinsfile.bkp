
pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        DEPLOY_HOST = '192.168.1.32'
        DEPLOY_USER = 'deploy'
        APP_DIR = '/opt/flask-app'
        IMAGE_NAME = 'flask-demo'
        CONTAINER_NAME = 'flask-demo'
        APP_PORT = '8080'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Prepare Remote Directory') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        ssh -o StrictHostKeyChecking=accept-new \
                          ${DEPLOY_USER}@${DEPLOY_HOST} \
                          "mkdir -p ${APP_DIR}"
                    '''
                }
            }
        }

        stage('Copy Application') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        scp -r app.py Dockerfile requirements.txt templates \
                          ${DEPLOY_USER}@${DEPLOY_HOST}:${APP_DIR}/
                    '''
                }
            }
        }

        stage('Build and Deploy') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        ssh ${DEPLOY_USER}@${DEPLOY_HOST} \
                          "cd ${APP_DIR} &&
                           docker build -t ${IMAGE_NAME}:${BUILD_NUMBER} . &&
                           docker rm -f ${CONTAINER_NAME} 2>/dev/null || true"
                    '''

                    sh '''
                        ssh ${DEPLOY_USER}@${DEPLOY_HOST} \
                          "docker run -d --name ${CONTAINER_NAME} \
                           --restart unless-stopped \
                           -p ${APP_PORT}:5000 \
                           ${IMAGE_NAME}:${BUILD_NUMBER}"
                    '''
                }
            }
        }

        stage('Health Check') {
            steps {
                sshagent(credentials: ['docker-server-ssh']) {
                    sh '''
                        ssh ${DEPLOY_USER}@${DEPLOY_HOST} \
                          "curl -fsS http://localhost:${APP_PORT}/health"
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'Flask deployment successful.'
        }
        failure {
            echo 'Deployment failed. Check Console Output.'
        }
    }
}
