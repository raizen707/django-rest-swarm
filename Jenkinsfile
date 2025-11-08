pipeline {
  agent any

  environment {
    REGISTRY = 'localhost:5000'
    APP_NAME = 'django-rest-swarm'
    COMMIT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
    IMAGE = "${REGISTRY}/${APP_NAME}:${COMMIT}"
    LATEST = "${REGISTRY}/${APP_NAME}:latest"
    STACK = 'djstack'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build image') {
      steps {
        script {
          docker.withServer('unix:///var/run/docker.sock') {
            def img = docker.build("${IMAGE}")
            img.push()
            img.push('latest')
          }
        }
      }
    }

    stage('Smoke test (container)') {
      steps {
        script {
          sh """
            cid=\$(docker run -d -p 18000:8000 ${IMAGE})
            sleep 4
            curl -sf http://localhost:18000/health
            docker rm -f \$cid
          """
        }
      }
    }

    stage('Deploy to Swarm') {
      steps {
        script {
          writeFile file: 'docker-stack.yml', text: """
version: '3.9'
services:
  api:
    image: ${LATEST}
    ports:
      - "8000:8000"
    environment:
      DJANGO_SECRET_KEY: \${DJANGO_SECRET_KEY:-prod-secret}
    networks: [webnet]
    deploy:
      replicas: 2
      restart_policy: { condition: on-failure }
      update_config: { parallelism: 1, order: start-first, delay: 5s }
networks:
  webnet:
    external: true
"""
          sh "docker stack deploy -c docker-stack.yml ${STACK}"
          sh "docker stack services ${STACK}"
        }
      }
    }
  }

  post {
    always {
      echo "Done"
    }
  }
}
