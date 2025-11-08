pipeline {
  agent any
  options { timestamps() }

  environment {
    // ---- Docker/Swarm ----
    REGISTRY  = 'localhost:5000'
    APP_NAME  = 'django-rest-swarm'
    STACK     = 'djstack'
    REPLICAS  = '2'
    LATEST    = "${REGISTRY}/${APP_NAME}:latest"

    // ---- Git ----
    GIT_URL    = 'https://github.com/raizen707/django-rest-swarm'
    GIT_BRANCH = 'master'   // change to 'main' if needed

    // ---- Kubernetes (toggle ON to deploy) ----
    USE_K8S              = 'true'         // set 'true' to enable K8s stages
    K8S_NAMESPACE        = 'default'
    K8S_APP_NAME         = 'django-rest-api'
    K8S_DEPLOY_REPLICAS  = '2'
    K8S_KUBECONFIG_CRED  = 'kubeconfig_file'

    // Expose Kubernetes via NodePort (optional testing)
    K8S_SERVICE_PORT     = '8081'         // cluster service port
    K8S_NODE_PORT        = '31080'        // host port (30000–32767)

    // K8s image reference mode: 'local' (no pull) or 'registry'
    K8S_IMAGE_MODE       = 'local'
  }

  stages {
    stage('Checkout (clean)') {
      steps {
        deleteDir()
        sh 'git --version'
        sh 'git init && git remote add origin "${GIT_URL}" && git fetch --depth=1 origin "${GIT_BRANCH}" && git checkout -B "${GIT_BRANCH}" FETCH_HEAD'
      }
    }

    stage('Build & Push Image') {
      steps {
        sh 'docker version'
        script { env.IMAGE = "${env.REGISTRY}/${env.APP_NAME}:${env.BUILD_NUMBER}" }
        sh """
          set -e
          docker build -t ${IMAGE} .
          docker push ${IMAGE}
          docker tag  ${IMAGE} ${LATEST}
          docker push ${LATEST}
          # local tag for K8s 'local' mode
          docker tag ${LATEST} ${APP_NAME}:latest
          docker image ls | grep ${APP_NAME} || true
        """
      }
    }

    stage('Smoke Test') {
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'FAILURE') {
          sh """
            set -e
            CID=\$(docker run -d -p 18000:8000 ${LATEST})
            echo "Temp container: \$CID"
            for i in \$(seq 1 30); do
              if curl -sf http://host.docker.internal:18000/health >/dev/null; then
                echo "Smoke test passed"; break
              fi
              sleep 2
              if [ \$i -eq 30 ]; then
                echo "Smoke test FAILED"
                docker logs "\$CID" || true
                docker rm -f "\$CID" || true
              fi
            done
            docker rm -f "\$CID"
          """
        }
      }
    }

    stage('Prepare Swarm Stack File') {
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
      steps {
        sh '''
          set -e
          if ! docker network ls --format '{{.Name}}' | grep -q '^webnet$'; then
            docker network create -d overlay webnet
          fi
          docker stack deploy -c docker-stack.yml ${STACK}
          docker stack services ${STACK}
        '''
      }
    }

    // -------------------- KUBERNETES ADD-ON --------------------
    stage('Prepare K8s Manifests') {
      when { expression { env.USE_K8S?.toLowerCase() == 'true' } }
      steps {
        script {
          env.K8S_IMAGE = (env.K8S_IMAGE_MODE?.toLowerCase() == 'registry')
            ? "host.docker.internal:5000/${env.APP_NAME}:latest"
            : "${env.APP_NAME}:latest" // local mode (no pull)
        }
        writeFile file: 'k8s-deploy.yaml', text: """
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${K8S_APP_NAME}
  namespace: ${K8S_NAMESPACE}
  labels:
    app: ${K8S_APP_NAME}
spec:
  replicas: ${K8S_DEPLOY_REPLICAS}
  revisionHistoryLimit: 2
  selector:
    matchLabels:
      app: ${K8S_APP_NAME}
  template:
    metadata:
      labels:
        app: ${K8S_APP_NAME}
    spec:
      containers:
      - name: api
        image: ${K8S_IMAGE}
        imagePullPolicy: ${K8S_IMAGE_MODE == 'local' ? 'IfNotPresent' : 'Always'}
        env:
        - name: DJANGO_SECRET_KEY
          value: "prod-secret"
        ports:
        - containerPort: 8000
        readinessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 15
          periodSeconds: 5
          timeoutSeconds: 2
          failureThreshold: 12
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 2
          failureThreshold: 6
---
apiVersion: v1
kind: Service
metadata:
  name: ${K8S_APP_NAME}
  namespace: ${K8S_NAMESPACE}
spec:
  selector:
    app: ${K8S_APP_NAME}
  type: NodePort
  ports:
  - name: http
    port: ${K8S_SERVICE_PORT}
    targetPort: 8000
    nodePort: ${K8S_NODE_PORT}
"""
      }
    }

    stage('Deploy to Kubernetes') {
      when { expression { env.USE_K8S?.toLowerCase() == 'true' } }
      steps {
        withCredentials([file(credentialsId: "${K8S_KUBECONFIG_CRED}", variable: 'KUBECONFIG_FILE')]) {
          sh """
            set -e
            kubectl --kubeconfig "$KUBECONFIG_FILE" version --client
            kubectl --kubeconfig "$KUBECONFIG_FILE" get ns ${K8S_NAMESPACE} >/dev/null 2>&1 || \
              kubectl --kubeconfig "$KUBECONFIG_FILE" create namespace ${K8S_NAMESPACE}
            kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} apply -f k8s-deploy.yaml
            sleep 5
            kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} rollout status deploy/${K8S_APP_NAME} --timeout=300s
            kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} get pods -o wide -l app=${K8S_APP_NAME}
            kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} get svc/${K8S_APP_NAME}
          """
        }
      }
    }
    // ------------------ END KUBERNETES ADD-ON ------------------
  }

  post {
    success {
      echo "Swarm: http://localhost:8000/health"
      echo "K8s:   http://localhost:${K8S_NODE_PORT}/health (NodePort ${K8S_NODE_PORT}, service port ${K8S_SERVICE_PORT})"
    }
    unstable {
      script {
        if (env.USE_K8S?.toLowerCase() == 'true') {
          withCredentials([file(credentialsId: env.K8S_KUBECONFIG_CRED, variable: 'KUBECONFIG_FILE')]) {
            sh """
              set +e
              echo "=== K8s DEBUG (unstable) ==="
              kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} describe deploy/${K8S_APP_NAME}
              kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} get pods -l app=${K8S_APP_NAME} -o name | \
                xargs -I{} sh -c 'echo "--- {} ---"; kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} describe {}'
              for p in \$(kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} get pods -l app=${K8S_APP_NAME} -o name); do
                kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} logs "\$p" --tail=200 || true
              done
            """
          }
        }
      }
    }
    failure {
      script {
        if (env.USE_K8S?.toLowerCase() == 'true') {
          withCredentials([file(credentialsId: env.K8S_KUBECONFIG_CRED, variable: 'KUBECONFIG_FILE')]) {
            sh """
              set +e
              echo "=== K8s DEBUG (failure) ==="
              kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} describe deploy/${K8S_APP_NAME}
              kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} get pods -l app=${K8S_APP_NAME} -o name | \
                xargs -I{} sh -c 'echo "--- {} ---"; kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} describe {}'
              for p in \$(kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} get pods -l app=${K8S_APP_NAME} -o name); do
                kubectl --kubeconfig "$KUBECONFIG_FILE" -n ${K8S_NAMESPACE} logs "\$p" --tail=200 || true
              done
            """
          }
        }
      }
    }
  }
}
