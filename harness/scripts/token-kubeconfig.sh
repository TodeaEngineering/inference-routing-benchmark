#!/usr/bin/env bash
# Make kubectl and helm independent of the gcloud login. That login expires
# within a day, and a long matrix run stops when it does.
#
#   bash harness/scripts/token-kubeconfig.sh            # switch to a service account token
#   bash harness/scripts/token-kubeconfig.sh renew      # a fresh token, before the old one expires
#   bash harness/scripts/token-kubeconfig.sh restore    # back to the gcloud login
#
# The first call creates the service account routing-bench-runner in
# kube-system and gives it the cluster-admin role, which the benchmark needs to
# install charts and to label the GPU node. Its token is valid for DURATION and
# is written only into the kubeconfig, which gets mode 600. The script never
# prints the token. The account goes away with the cluster.
#
# The switch replaces the kubeconfig in one step, so a run that is under way
# picks the token up with its next kubectl call.
set -euo pipefail

: "${KUBECONFIG:=$HOME/.kube/gpu-sharing-demo}"
export KUBECONFIG
: "${DURATION:=48h}"
ACCOUNT=routing-bench-runner
BACKUP="$KUBECONFIG.gcloud"

# Write a kubeconfig for the current cluster that authenticates with the token
# on standard input, and print when the token expires.
write_config() {
  local server ca name
  server=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
  ca=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
  name=$(kubectl config current-context)
  SERVER=$server CA=$ca NAME=$name ACCOUNT=$ACCOUNT TARGET=$KUBECONFIG python3 -c '
import base64, datetime, json, os, sys
token = sys.stdin.read().strip()
if token.count(".") != 2:
    sys.exit("no token on standard input")
claims = json.loads(base64.urlsafe_b64decode(token.split(".")[1] + "=="))
name, account = os.environ["NAME"], os.environ["ACCOUNT"]
config = {
    "apiVersion": "v1", "kind": "Config", "current-context": name,
    "clusters": [{"name": name, "cluster": {"server": os.environ["SERVER"],
                                           "certificate-authority-data": os.environ["CA"]}}],
    "users": [{"name": account, "user": {"token": token}}],
    "contexts": [{"name": name, "context": {"cluster": name, "user": account}}],
}
target = os.environ["TARGET"]
fd = os.open(target + ".new", os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(fd, "w") as out:
    json.dump(config, out, indent=1)
os.replace(target + ".new", target)
print("token valid until", datetime.datetime.fromtimestamp(claims["exp"]).strftime("%Y-%m-%d %H:%M"), "local time")
'
}

case "${1:-switch}" in
  switch)
    if ! grep -q 'gke-gcloud-auth-plugin' "$KUBECONFIG"; then
      echo "$KUBECONFIG does not use the gcloud login. Use renew for a fresh token." >&2
      exit 1
    fi
    kubectl -n kube-system create serviceaccount "$ACCOUNT" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl create clusterrolebinding "$ACCOUNT" --clusterrole=cluster-admin \
      --serviceaccount="kube-system:$ACCOUNT" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    cp -p "$KUBECONFIG" "$BACKUP"
    kubectl -n kube-system create token "$ACCOUNT" --duration="$DURATION" | write_config
    echo "kubectl now acts as $(kubectl auth whoami -o jsonpath='{.status.userInfo.username}')"
    echo "The gcloud version of the kubeconfig is kept as $BACKUP" ;;
  renew)
    kubectl -n kube-system create token "$ACCOUNT" --duration="$DURATION" | write_config ;;
  restore)
    [ -f "$BACKUP" ] || { echo "No $BACKUP to restore." >&2; exit 1; }
    cp -p "$BACKUP" "$KUBECONFIG"
    echo "Back to the gcloud login. The service account still exists; delete it with:"
    echo "  kubectl delete clusterrolebinding $ACCOUNT; kubectl -n kube-system delete serviceaccount $ACCOUNT" ;;
  *)
    echo "usage: bash $0 [switch|renew|restore]" >&2
    exit 1 ;;
esac
