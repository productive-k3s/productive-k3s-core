#!/usr/bin/env bash

: "${PRODUCTIVE_K3S_DISTRO:=k3s}"
: "${PRODUCTIVE_K3S_ENGINE:=native}"

pk3s_runtime_validate_selection() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s|rke2)
      ;;
    *)
      printf 'Unsupported cluster distro: %s\n' "${PRODUCTIVE_K3S_DISTRO}" >&2
      return 1
      ;;
  esac

  case "${PRODUCTIVE_K3S_ENGINE}" in
    native|k3sup)
      ;;
    *)
      printf 'Unsupported cluster engine: %s\n' "${PRODUCTIVE_K3S_ENGINE}" >&2
      return 1
      ;;
  esac

  if [[ "${PRODUCTIVE_K3S_DISTRO}" == "rke2" && "${PRODUCTIVE_K3S_ENGINE}" != "native" ]]; then
    printf 'Unsupported distro/engine combination: %s/%s\n' "${PRODUCTIVE_K3S_DISTRO}" "${PRODUCTIVE_K3S_ENGINE}" >&2
    return 1
  fi
}

pk3s_runtime_distro_label() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf 'k3s' ;;
    rke2) printf 'rke2' ;;
  esac
}

pk3s_runtime_distro_display_name() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf 'K3S' ;;
    rke2) printf 'RKE2' ;;
  esac
}

pk3s_runtime_cluster_label() {
  printf '%s' "$(pk3s_runtime_distro_label)"
}

pk3s_runtime_server_service() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf 'k3s' ;;
    rke2) printf 'rke2-server' ;;
  esac
}

pk3s_runtime_agent_service() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf 'k3s-agent' ;;
    rke2) printf 'rke2-agent' ;;
  esac
}

pk3s_runtime_system_kubeconfig_path() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf '/etc/rancher/k3s/k3s.yaml' ;;
    rke2) printf '/etc/rancher/rke2/rke2.yaml' ;;
  esac
}

pk3s_runtime_default_user_kubeconfig_path() {
  printf '%s/.kube/%s.yaml' "${HOME}" "${PRODUCTIVE_K3S_DISTRO}"
}

pk3s_runtime_default_ingress_class() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf 'traefik' ;;
    rke2) printf 'nginx' ;;
  esac
}

pk3s_runtime_join_token_path() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf '/var/lib/rancher/k3s/server/node-token' ;;
    rke2) printf '/var/lib/rancher/rke2/server/node-token' ;;
  esac
}

pk3s_runtime_uninstall_script_path() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf '/usr/local/bin/k3s-uninstall.sh' ;;
    rke2) printf '/usr/bin/rke2-uninstall.sh' ;;
  esac
}

pk3s_runtime_killall_script_path() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf '/usr/local/bin/k3s-killall.sh' ;;
    rke2) printf '/usr/bin/rke2-killall.sh' ;;
  esac
}

pk3s_runtime_state_dirs() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s)
      printf '%s\n' \
        /etc/rancher/k3s \
        /var/lib/rancher/k3s \
        /var/lib/kubelet \
        /etc/cni/net.d \
        /var/lib/cni \
        /run/flannel \
        /run/k3s
      ;;
    rke2)
      printf '%s\n' \
        /etc/rancher/rke2 \
        /var/lib/rancher/rke2 \
        /var/lib/kubelet \
        /etc/cni/net.d \
        /var/lib/cni \
        /run/flannel
      ;;
  esac
}

pk3s_runtime_embedded_kubectl_bin() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf 'k3s' ;;
    rke2) printf '/var/lib/rancher/rke2/bin/kubectl' ;;
  esac
}

pk3s_runtime_addon_kubectl_mode() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf 'k3s' ;;
    rke2) printf 'kubectl' ;;
  esac
}

pk3s_runtime_addon_kubectl_bin() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf 'kubectl' ;;
    rke2) printf '/var/lib/rancher/rke2/bin/kubectl' ;;
  esac
}

pk3s_runtime_kubectl_hint() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s) printf 'sudo k3s kubectl' ;;
    rke2) printf 'sudo /var/lib/rancher/rke2/bin/kubectl --kubeconfig %s' "$(pk3s_runtime_system_kubeconfig_path)" ;;
  esac
}

pk3s_runtime_server_active() {
  systemctl is-active --quiet "$(pk3s_runtime_server_service)" >/dev/null 2>&1
}

pk3s_runtime_agent_active() {
  systemctl is-active --quiet "$(pk3s_runtime_agent_service)" >/dev/null 2>&1
}

pk3s_runtime_component_active() {
  local mode="${1:-server}"
  if [[ "${mode}" == "agent" ]]; then
    pk3s_runtime_agent_active
  else
    pk3s_runtime_server_active
  fi
}

pk3s_runtime_kubectl() {
  case "${PRODUCTIVE_K3S_DISTRO}" in
    k3s)
      sudo k3s kubectl "$@"
      ;;
    rke2)
      sudo "$(pk3s_runtime_embedded_kubectl_bin)" --kubeconfig "$(pk3s_runtime_system_kubeconfig_path)" "$@"
      ;;
  esac
}
