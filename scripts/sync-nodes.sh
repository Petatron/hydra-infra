#!/usr/bin/env bash
# sync-nodes.sh — Orchestrates the full VM ↔ K8s lifecycle:
#   plan    — terraform plan only (dry-run)
#   apply   — drain removed nodes → terraform apply → join new nodes
#   destroy — drain all nodes → terraform destroy
set -euo pipefail

ACTION="${1:-apply}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")"

CONTROL_PLANE_IP="${CONTROL_PLANE_IP:-192.168.15.10}"
CONTROL_PLANE_USER="${CONTROL_PLANE_USER:-yibofu}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_USER="${SSH_USER:-yibofu}"
KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"

log()  { echo ">>> $*"; }
warn() { echo "!!! $*" >&2; }

cd "$TF_DIR"
terraform init -input=false -no-color

# ---------- helpers --------------------------------------------------------

drain_node() {
  local node="$1"
  log "Draining K8s node: $node"
  kubectl --kubeconfig="$KUBECONFIG" drain "$node" \
    --ignore-daemonsets --delete-emptydir-data --timeout=120s 2>/dev/null || true
  kubectl --kubeconfig="$KUBECONFIG" delete node "$node" 2>/dev/null || true
}

wait_for_cloud_init() {
  local ip="$1" name="$2"
  log "Waiting for $name ($ip) cloud-init to finish..."
  for attempt in $(seq 1 60); do
    if ssh -i "$SSH_KEY" $SSH_OPTS "$SSH_USER@$ip" \
       "cloud-init status" 2>/dev/null | grep -q "done"; then
      log "$name cloud-init complete"
      return 0
    fi
    sleep 10
  done
  warn "Timed out waiting for cloud-init on $name ($ip)"
  return 1
}

join_node() {
  local ip="$1" name="$2" join_cmd="$3"
  log "Joining $name ($ip) to cluster..."
  ssh -i "$SSH_KEY" $SSH_OPTS "$SSH_USER@$ip" "sudo $join_cmd"
}

label_node() {
  local name="$1"
  local labels
  labels=$(terraform output -json node_labels | jq -r 'to_entries[] | "\(.key)=\(.value)"')
  for label in $labels; do
    kubectl --kubeconfig="$KUBECONFIG" label node "$name" "$label" --overwrite 2>/dev/null || true
  done
}

get_vm_ip() {
  local name="$1"
  terraform output -json worker_ips | jq -r ".[\"$name\"][0] // empty"
}

# ---------- actions --------------------------------------------------------

do_plan() {
  terraform plan
}

do_apply() {
  set +e
  terraform plan -out=tfplan -detailed-exitcode -no-color
  local plan_exit=$?
  set -e

  case $plan_exit in
    0) log "No infrastructure changes."; return 0 ;;
    1) warn "Terraform plan failed."; return 1 ;;
  esac

  local nodes_to_remove nodes_to_add
  nodes_to_remove=$(terraform show -json tfplan | \
    jq -r '[.resource_changes[]? |
      select(.type == "libvirt_domain") |
      select(.change.actions[] == "delete") |
      .change.before.name // empty] | unique[]' 2>/dev/null) || true

  nodes_to_add=$(terraform show -json tfplan | \
    jq -r '[.resource_changes[]? |
      select(.type == "libvirt_domain") |
      select(.change.actions[] == "create") |
      .change.after.name // empty] | unique[]' 2>/dev/null) || true

  if [ -n "$nodes_to_remove" ]; then
    log "Nodes to remove: $nodes_to_remove"
    for node in $nodes_to_remove; do
      drain_node "$node"
    done
  fi

  log "Applying Terraform plan..."
  terraform apply -auto-approve tfplan

  if [ -z "$nodes_to_add" ]; then
    log "No new nodes to join."
    return 0
  fi

  log "Nodes to add: $nodes_to_add"

  log "Generating kubeadm join token on control plane..."
  local join_cmd
  join_cmd=$(ssh -i "$SSH_KEY" $SSH_OPTS \
    "$CONTROL_PLANE_USER@$CONTROL_PLANE_IP" \
    "sudo kubeadm token create --print-join-command")

  for node in $nodes_to_add; do
    local ip
    ip=$(get_vm_ip "$node")
    if [ -z "$ip" ]; then
      ip=$(sudo virsh domifaddr "$node" --source agent 2>/dev/null | \
        awk '/ipv4/{gsub(/\/.*/, "", $4); print $4}')
    fi
    if [ -z "$ip" ]; then
      warn "Could not determine IP for $node — skipping join"
      continue
    fi

    wait_for_cloud_init "$ip" "$node"
    join_node "$ip" "$node" "$join_cmd"
    label_node "$node"
  done

  log "Waiting for nodes to become Ready..."
  sleep 20
  kubectl --kubeconfig="$KUBECONFIG" get nodes -o wide
}

do_destroy() {
  local managed_nodes
  managed_nodes=$(terraform output -json worker_names 2>/dev/null | jq -r '.[]' 2>/dev/null) || true

  if [ -n "$managed_nodes" ]; then
    for node in $managed_nodes; do
      drain_node "$node"
    done
  fi

  terraform destroy -auto-approve
}

# ---------- main -----------------------------------------------------------

case "$ACTION" in
  plan)    do_plan    ;;
  apply)   do_apply   ;;
  destroy) do_destroy ;;
  *)
    echo "Usage: $0 {plan|apply|destroy}"
    exit 1
    ;;
esac
