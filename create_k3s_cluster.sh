#!/usr/bin/env bash
#./maestro/scripts/create_k3d_cluster.sh
set -euo pipefail

if [[ "${DEBUG:-}" == true ]]; then
  set -x
  helm_debug_args=(--debug)
else
  helm_debug_args=()
fi

K3D_HOST="${K3D_HOST:-"$(hostname -I | awk '{ print $1 }').nip.io"}"
K3D_CLUSTER_NAME="${K3D_CLUSTER_NAME:-"k3s-default"}"
K3D_KUBECONFIG="${K3D_KUBECONFIG:-"${K3D_CLUSTER_NAME}.kubeconfig.yaml"}"
K3D_CONNECT="${K3D_CONNECT:-true}"
K3D_PATH="${HOME}/.local/bin/k3d"

# https://github.com/k3d-io/k3d/releases
# renovate: datasource=github-releases depName=k3d packageName=k3d-io/k3d
K3D_VERSION="5.8.3"
# Must be one available in https://hub.docker.com/r/rancher/k3s/tags,
# Ensure it is valid with: docker pull rancher/k3s:v${K8S_VERSION}-k3s1
# renovate: datasource=github-releases depName=kubernetes packageName=kubernetes/kubernetes
K8S_VERSION="1.33.4"
# https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx?modal=changelog
# renovate: datasource=github-releases depName=ingress-nginx packageName=kubernetes/ingress-nginx extractVersion=^helm-chart-(?<version>.+)$
INGRESS_NGINX_VERSION="4.13.2"

# This ensure next time we call k3d, we will be using the one we installed
alias k3d='${K3D_PATH}'

# shellcheck disable=SC2310
if ! k3d version 2>/dev/null | grep -q "${K3D_VERSION}"; then
  echo "Installing K3D ${K3D_VERSION} to ${K3D_PATH}..." >&2
  # Install K3D
  mkdir -p "$(dirname "${K3D_PATH}")"
  rm -f "${K3D_PATH}"
  curl -fsSL --retry 5 --output "${K3D_PATH}" "https://arm.seli.gic.ericsson.se/artifactory/proj-river-3pp-github-remote/k3d-io/k3d/releases/download/v${K3D_VERSION}/k3d-linux-amd64"
  chmod +x "${K3D_PATH}"

  k3d version | grep -q "${K3D_PATH}"
else
  echo "Using K3D ${K3D_VERSION} already installed" >&2
fi

echo "Checking if ${K3D_HOST} resolves to a valid IP address..." >&2
getent hosts "${K3D_HOST}"

echo "Deleting k3d cluster ${K3D_CLUSTER_NAME} if it exists..." >&2
k3d cluster delete "${K3D_CLUSTER_NAME}"
rm -f "${K3D_KUBECONFIG}"

echo "Creating k3d cluster ${K3D_CLUSTER_NAME}..." >&2
K3D_FIX_DNS=1 k3d cluster create "${K3D_CLUSTER_NAME}" --config=<(
  # shellcheck disable=SC2312
  cat <<EOF
apiVersion: k3d.io/v1alpha5
kind: Simple

servers: 1
agents: 2
image: rancher/k3s:v${K8S_VERSION}-k3s1

registries:
  config: | # tell K3s to use this registry when pulling from DockerHub
    mirrors:
      "docker.io":
        endpoint:
          - "https://armdockerhub.rnd.ericsson.se"

kubeAPI:
  host: ${K3D_HOST}
  hostIP: 0.0.0.0
  hostPort: "6550"

ports:
  - port: 80:80
    nodeFilters:
      - loadbalancer
  - port: 443:443
    nodeFilters:
      - loadbalancer

options:
  k3d:
    wait: true
    timeout: 5m
  kubeconfig:
    updateDefaultKubeconfig: false
    switchCurrentContext: false
  k3s:
    extraArgs:
      - arg: --disable=traefik
        nodeFilters:
          - server:*
EOF
)

echo "Exporting k3d cluster ${K3D_CLUSTER_NAME} kubeconfig to ${K3D_KUBECONFIG}..." >&2
k3d kubeconfig get "${K3D_CLUSTER_NAME}" >"${K3D_KUBECONFIG}"
chmod go-r "${K3D_KUBECONFIG}"

export KUBECONFIG="${K3D_KUBECONFIG}"

echo "Installing Ingress NGINX ${INGRESS_NGINX_VERSION}..." >&2
helm upgrade --install --wait --wait-for-jobs "${helm_debug_args[@]}" \
  ingress-nginx \
  "https://arm.seli.gic.ericsson.se/artifactory/proj-river-3pp-github-remote/kubernetes/ingress-nginx/releases/download/helm-chart-${INGRESS_NGINX_VERSION}/ingress-nginx-${INGRESS_NGINX_VERSION}.tgz" \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.watchIngressWithoutClass=true \
  --set controller.allowSnippetAnnotations=true \
  --set controller.config.proxy-buffer-size=16k \
  --set controller.config.proxy-busy-buffers-size=16k

echo "Checking if NGINX at https://${K3D_HOST} is reachable..." >&2
timeout 10s curl --insecure -sSL "https://${K3D_HOST}" >/dev/null

echo "✅ The K3D cluster ${K3D_CLUSTER_NAME} was successfully created." >&2
echo >&2

if [[ "${K3D_CONNECT}" == true ]]; then
  echo "Connecting the currrent kubeconfig to the k3d cluster ${K3D_CLUSTER_NAME}..." >&2
  k3d kubeconfig merge --kubeconfig-merge-default "${K3D_CLUSTER_NAME}"
else
  echo "💡 You can connect to it by running the following command:" >&2
  echo "👉 export KUBECONFIG=\"${K3D_KUBECONFIG}\" && kubectl get nodes" >&2
fi
echo >&2

echo "💡 You can now use '${K3D_HOST}' as Maestro's INGRESS_HOST:" >&2
echo "👉 export INGRESS_HOST=\"${K3D_HOST}\"" >&2
