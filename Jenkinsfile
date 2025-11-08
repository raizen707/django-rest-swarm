pipeline {
  agent any

  options {
    timestamps()
    ansiColor('xterm')
  }

  environment {
    // Adjust if you use a different registry or image name
    REGISTRY = 'localhost:5000'
    APP_NAME = 'django-rest-swarm'
    STACK    = 'djstack'
    REPLICAS = '2'
    LATEST   = "${REGISTRY}/${APP_NAME}:latest"
  }

  stages {
    stage('Checkout') {
      steps {
        checkout scm
        sh 'git --version'
      }
    }

    stage('Build & Push Image') {
      agent {
        docker {
          image 'docker:27-git'                      // Docker CLI + Git (Alpine)
          args  '-v /var/run/docker.sock:/var/run/docker.sock'
          reuseNode true
        }
      }
      environment {
        COMMIT = "${env.BUILD_NUMBER}"              // or use `git rev-parse --short HEAD`
        IMAGE  = "${REGISTRY}/${APP_NAME}:${BUILD_NUMBER}"
      }
      steps {
        sh 'docker version'
        // Build & push
        sh """
          docker build -t "${IMAGE}" .
          docker push "${IMAGE}"
          docker tag  "${IMAGE}" "${LATEST}"
          docker push "${LATEST}"
        """
      }
    }

    stage('Smoke Test') {
      agent {
        docker {
          image 'docker:27-git'
          args  '-v /var/run/docker.sock:/var/run/docker.sock'
          reuseNode true
        }
      }
      steps {
        // Alpine container used as the agent; install curl to perform the test
        sh 'apk add --no-cache curl'

        // Run a temporary container on host port 18000, probe /health via host.docker.internal (Windows/Mac Desktop)
        sh '''
          set -e
          CID=$(docker run -d -p 18000:8000 '"${LATEST}"')
          echo "Temp container: $CID"
          # small wait for gunicorn to boot
          for i in $(seq 1 20); do
            if curl -sf http://host.docker.internal:18000/health >/dev/null; then
              echo "Smoke test passed"
              break
            fi
            sleep 1
            if [ $i -eq 20 ]; then
              echo "Smoke test FAILED"
              docker logs "$CID" || true
              docker rm -f "$CID" || true
              exit 1
            fi
          done
          docker rm -f "$CID"
        '''
      }
    }

    stage('Prepare Stack File') {
      agent {
        docker {
          image 'docker:27-cli'
          args  '-v /var/run/docker.sock:/var/run/docker.sock'
          reuseNode true
        }
      }
      steps {
        // Write (or overwrite) stack file pointing to :latest image
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
      replicas: ${REPLICAS}
      restart_policy: { condition: on-failure }
      update_config: { parallelism: 1, order: start-first, delay: 5s }
networks:
  webnet:
    external: true
"""
      }
    }

    stage('Deploy to Swarm') {
      agent {
        docker {
          image 'docker:27-cli'
          args  '-v /var/run/docker.sock:/var/run/docker.sock'
          reuseNode true
        }
      }
      steps {
        // Ensure overlay network exists, then deploy
        sh '''
          set -e
          if ! docker network ls --format '{{.Name}}' | grep -q '^webnet$'; then
            docker network create -d overlay webnet
          fi
          docker stack deploy -c docker-stack.yml '"${STACK}"'
          docker stack services '"${STACK}"'
        '''
      }
    }
  }

  post {
    success {
      echo "Deployed ${LATEST} to stack ${STACK} with ${REPLICAS} replicas."
      echo "Test endpoints: http://localhost:8000/health  http://localhost:8000/hello"
    }
    failure {
      echo "Pipeline failed. Check stage logs above."
    }
    always {
      script {
        currentBuild.displayName = "#${env.BUILD_NUMBER} ${env.BRANCH_NAME ?: ''}".trim()
      }
    }
  }
}
