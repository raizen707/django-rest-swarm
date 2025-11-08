pipeline {
  agent any
  options { timestamps() }

  environment {
    // ---- Adjust to your setup ----
    REGISTRY   = 'localhost:5000'
    APP_NAME   = 'django-rest-swarm'
    STACK      = 'djstack'
    REPLICAS   = '2'
    LATEST     = "${REGISTRY}/${APP_NAME}:latest"

    // Public repo (no creds). If private, add Jenkins creds and switch logic below.
    GIT_URL    = 'https://github.com/raizen707/django-rest-swarm'
    GIT_BRANCH = 'master'   // change to 'main' if your repo uses main
  }

  stages {
    stage('Checkout (clean)') {
      agent {
        docker {
          image 'docker:27'                                // Alpine + Docker CLI
          args  '-v /var/run/docker.sock:/var/run/docker.sock'
          reuseNode true
        }
      }
      steps {
        sh 'apk add --no-cache git'
        deleteDir()
        sh 'git --version'
        // Public repo shallow fetch
        sh 'git init && git remote add origin "${GIT_URL}" && git fetch --depth=1 origin "${GIT_BRANCH}" && git checkout -B "${GIT_BRANCH}" FETCH_HEAD'

        // If PRIVATE repo, replace the three lines above with:
        // withCredentials([string(credentialsId: "github_token", variable: "GITHUB_TOKEN")]) {
        //   sh """
        //     git init
        //     git config http.https://github.com/.extraheader "AUTHORIZATION: basic $(echo -n x-access-token:${GITHUB_TOKEN} | base64 -w0)"
        //     git remote add origin ${GIT_URL}
        //     git fetch --depth=1 origin ${GIT_BRANCH}
        //     git checkout -B ${GIT_BRANCH} FETCH_HEAD
        //   """
        // }
      }
    }

    stage('Build & Push Image') {
      agent {
        docker {
          image 'docker:27'
          args  '-v /var/run/docker.sock:/var/run/docker.sock'
          reuseNode true
        }
      }
      environment {
        IMAGE = "${REGISTRY}/${APP_NAME}:${BUILD_NUMBER}"
      }
      steps {
        sh 'docker version'
        sh """
          set -e
          docker build -t ${IMAGE} .
          docker push ${IMAGE}
          docker tag  ${IMAGE} ${LATEST}
          docker push ${LATEST}
        """
      }
    }

    stage('Smoke Test') {
      agent {
        docker {
          image 'docker:27'
          args  '-v /var/run/docker.sock:/var/run/docker.sock'
          reuseNode true
        }
      }
      steps {
        sh 'apk add --no-cache curl'
        sh """
          set -e
          CID=\$(docker run -d -p 18000:8000 ${LATEST})
          echo "Temp container: \$CID"
          for i in \$(seq 1 20); do
            if curl -sf http://host.docker.internal:18000/health >/dev/null; then
              echo "Smoke test passed"; break
            fi
            sleep 1
            if [ \$i -eq 20 ]; then
              echo "Smoke test FAILED"
              docker logs "\$CID" || true
              docker rm -f "\$CID" || true
              exit 1
            fi
          done
          docker rm -f "\$CID"
        """
      }
    }

    stage('Prepare Stack File') {
      agent {
        docker {
          image 'docker:27'
          args  '-v /var/run/docker.sock:/var/run/docker.sock'
          reuseNode true
        }
      }
      steps {
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
          image 'docker:27'
          args  '-v /var/run/docker.sock:/var/run/docker.sock'
          reuseNode true
        }
      }
      steps {
        sh """
          set -e
          if ! docker network ls --format '{{.Name}}' | grep -q '^webnet$'; then
            docker network create -d overlay webnet
          fi
          docker stack deploy -c docker-stack.yml ${STACK}
          docker stack services ${STACK}
        """
      }
    }
  }

  post {
    success {
      echo "Deployed ${LATEST} to stack ${STACK} with ${REPLICAS} replicas."
      echo "Test: http://localhost:8000/health  http://localhost:8000/hello"
    }
    failure {
      echo "Pipeline failed. Check the stage logs for details."
    }
  }
}
