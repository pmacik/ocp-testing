#!/bin/bash -ex

export PATH=$PATH:$(pwd)
export KUBECONFIG

# 0. Get Helm CLI

if [ ! -f ./helm ]; then
    curl -L -o helm https://mirror.openshift.com/pub/openshift-v4/clients/helm/latest/helm-linux-amd64
    chmod +x ./helm
fi

# 1. Setup a nexus repository:
./helm repo add sonatype https://sonatype.github.io/helm3-charts || echo Repo already added

./helm install nexus-helm-repo sonatype/nexus-repository-manager --version 29.0.0 --set persistence.enabled=false --set nexus.securityContext="" || echo Chart already installed

oc expose svc nexus-helm-repo-nexus-repository-manager || echo Repo already exposed

oc rollout status -w deployment/nexus-helm-repo-nexus-repository-manager

# 2. Create helm repo:
curl -u admin:$(oc exec deployment/nexus-helm-repo-nexus-repository-manager -- cat /nexus-data/admin.password) -X POST "$(oc get route nexus-helm-repo-nexus-repository-manager -o jsonpath='{.spec.host}')/service/rest/v1/repositories/helm/hosted" -H  "accept: application/json" -H  "Content-Type: application/json" -d "{  \"name\": \"helmtest\",  \"online\": true,  \"storage\": {    \"blobStoreName\": \"default\",    \"strictContentTypeValidation\": true,    \"writePolicy\": \"allow_once\"  },  \"cleanup\": {    \"policyNames\": [      \"string\"    ]  }}"

# 3. Upload content:
curl https://charts.mirantis.com/charts/nginx-0.1.0.tgz -o nginx-0.1.0.tgz
curl -u admin:$(oc exec deployment/nexus-helm-repo-nexus-repository-manager -- cat /nexus-data/admin.password) "$(oc get route nexus-helm-repo-nexus-repository-manager -o jsonpath='{.spec.host}')/repository/helmtest/" --upload-file nginx-0.1.0.tgz -v

# 4. Create HelmChartRepository:
cat > hcr.yaml <<EOF
apiVersion: helm.openshift.io/v1beta1
kind: HelmChartRepository
metadata:
  name: nexus-helm-repo
spec:
  connectionConfig:
    url: "http://$(oc get routes.route.openshift.io nexus-helm-repo-nexus-repository-manager -o jsonpath='{.spec.host}')/repository/helmtest"
EOF

# 5.
echo "You can use the following YAML to create to configure a Helm Chart Repository in OpenShift:"
cat hcr.yaml
echo "or by running: oc apply -f hcr.yaml"
echo "After the repository is configured, login to developer console and try to install the helm chart"
echo "[Developer Console] -> Add -> Helm Chart -> Nginx v0.1.0"