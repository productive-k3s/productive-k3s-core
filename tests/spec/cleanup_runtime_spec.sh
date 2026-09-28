# shellcheck shell=bash disable=SC2016
Describe 'cleanup runtime helpers'
  SCRIPT="$SHELLSPEC_PROJECT_ROOT/scripts/cleanup.sh"
  RUNNER="$SHELLSPEC_PROJECT_ROOT/tests/helpers/run-bootstrap-lib.sh"

  It 'unmounts runtime mount points before removing runtime state directories'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PRODUCTIVE_K3S_DISTRO=rke2
      capture_file="$(mktemp)"
      sudo() { printf "sudo:%s\n" "$*" >>"${capture_file}"; }
      runtime_mount_points() {
        printf "%s\n" \
          /var/lib/kubelet/plugins/kubernetes.io/csi/driver.longhorn.io/abc/globalmount \
          /var/lib/kubelet/pods/pod-a/volumes/kubernetes.io~projected/kube-api-access \
          /run/flannel/subnet.env \
          /tmp/not-managed
      }
      pk3s_runtime_state_dirs() {
        printf "%s\n" /var/lib/kubelet /run/flannel
      }
      unmount_runtime_state_dirs
      cat "${capture_file}"'
    The status should equal 0
    The output should include 'sudo:umount /var/lib/kubelet/plugins/kubernetes.io/csi/driver.longhorn.io/abc/globalmount'
    The output should include 'sudo:umount /var/lib/kubelet/pods/pod-a/volumes/kubernetes.io~projected/kube-api-access'
    The output should include 'sudo:umount /run/flannel/subnet.env'
    The output should not include '/tmp/not-managed'
  End

  It 'runs uninstall killall unmount and rm for runtime cleanup'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      PRODUCTIVE_K3S_DISTRO=rke2
      tmpdir="$(mktemp -d)"
      capture_file="$(mktemp)"
      touch "${tmpdir}/rke2-uninstall.sh" "${tmpdir}/rke2-killall.sh"
      chmod +x "${tmpdir}/rke2-uninstall.sh" "${tmpdir}/rke2-killall.sh"
      sudo() { printf "sudo:%s\n" "$*" >>"${capture_file}"; }
      runtime_mount_points() { printf "%s\n" /var/lib/kubelet/pods/pod-a/volumes/kubernetes.io~projected/kube-api-access; }
      pk3s_runtime_state_dirs() { printf "%s\n" /etc/rancher/rke2 /var/lib/kubelet; }
      pk3s_runtime_uninstall_script_path() { printf "%s/rke2-uninstall.sh" "${tmpdir}"; }
      pk3s_runtime_killall_script_path() { printf "%s/rke2-killall.sh" "${tmpdir}"; }
      uninstall_runtime
      cat "${capture_file}"'
    The status should equal 0
    The output should include 'sudo:systemctl stop rke2-server'
    The output should include 'sudo:systemctl disable rke2-server'
    The output should include 'sudo:systemctl stop rke2-agent'
    The output should include 'sudo:systemctl disable rke2-agent'
    The output should include 'sudo:'
    The output should include 'rke2-uninstall.sh'
    The output should include 'rke2-killall.sh'
    The output should include 'sudo:umount /var/lib/kubelet/pods/pod-a/volumes/kubernetes.io~projected/kube-api-access'
    The output should include 'sudo:rm -rf /etc/rancher/rke2'
    The output should include 'sudo:rm -rf /var/lib/kubelet'
    The output should include 'sudo:systemctl daemon-reload'
    The output should include 'sudo:systemctl reset-failed'
  End

  It 'returns success after printing a plan without applying cleanup'
    When run /usr/bin/env PRODUCTIVE_K3S_DISTRO=k3s "$SCRIPT" --plan
    The status should equal 0
    The output should include '[INFO] Clean plan'
    The output should include 'Uninstall k3s and remove local runtime state directories'
  End

  It 'cancels apply cleanup when confirmation is declined'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      AUTO_APPROVE=n
      FORCE_CONFIRM=n
      prompt_yesno() { printf -v "$1" n; }
      apply_cleanup'
    The status should equal 0
    The stderr should include '[WARN] Cleanup cancelled.'
  End

  It 'applies cleanup with automatic confirmations'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      AUTO_APPROVE=y
      FORCE_CONFIRM=y
      sudo_keepalive() { printf "sudo_keepalive\n"; }
      run_stack_addon_clean_hooks() { printf "clean_hooks\n"; }
      uninstall_runtime() { printf "uninstall_runtime\n"; }
      apply_cleanup'
    The status should equal 0
    The output should include 'sudo_keepalive'
    The output should include 'clean_hooks'
    The output should include 'uninstall_runtime'
    The output should include '[INFO] Cleanup completed'
  End

  It 'runs stack addon clean hooks when they exist and skips missing hooks'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/stacks/base" "${repo}/addons/with-clean/scripts" "${repo}/addons/without-clean/scripts"
      cat >"${repo}/stacks/base/stack.yaml" <<EOF
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: base
spec:
  addons:
    - with-clean
    - without-clean
EOF
      cat >"${repo}/addons/with-clean/scripts/clean.sh" <<EOF
pk3s_addon_clean() {
  printf "hook-ran:%s\n" "\${PRODUCTIVE_K3S_STACK_NAME}"
}
EOF
      PRODUCTIVE_K3S_ADDONS_REPO_DIR="${repo}"
      PRODUCTIVE_K3S_STACK_NAME=base
      run_stack_addon_clean_hooks'
    The status should equal 0
    The output should include 'hook-ran:base'
    The stderr should include "Add-on 'without-clean' does not provide scripts/clean.sh; skipping."
  End

  It 'normalizes non-interactive yes/no and text prompts'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      printf "maybe\nhello\n" | {
        prompt_yesno answer "y" "Question?"
        prompt_text typed "Type word"
        printf "answer=%s typed=%s\n" "${answer}" "${typed}"
      }'
    The status should equal 0
    The output should include 'Question? [y] (y/n): Type word: answer=y typed=hello'
  End

  It 'tracks and cleans up cleanup sudo keepalive processes'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      tmpdir="$(mktemp -d)"
      mockbin="${tmpdir}/bin"
      mkdir -p "${mockbin}"
      cat >"${mockbin}/sudo" <<EOF
#!/usr/bin/env bash
exit 0
EOF
      chmod +x "${mockbin}/sudo"
      PATH="${mockbin}:$PATH"
      sudo_keepalive
      [[ -n "${SUDO_KA_PID}" ]]
      cleanup_exit
      printf "pid=%s\n" "${SUDO_KA_PID}"'
    The status should equal 0
    The output should include 'pid='
  End

  It 'prints cleanup help'
    When run /usr/bin/env PRODUCTIVE_K3S_DISTRO=k3s "$SCRIPT" --help
    The status should equal 0
    The output should include 'Usage:'
  End

  It 'rejects unknown cleanup arguments'
    When run /usr/bin/env PRODUCTIVE_K3S_DISTRO=k3s "$SCRIPT" --bad-option
    The status should equal 1
    The output should include 'Usage:'
    The stderr should include '[ERROR] Unknown argument: --bad-option'
  End

  It 'fails when a stack clean hook file misses the expected function'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/stacks/base" "${repo}/addons/broken/scripts"
      cat >"${repo}/stacks/base/stack.yaml" <<EOF
apiVersion: addons.productive-k3s.io/v1
kind: Stack
metadata:
  name: base
spec:
  addons:
    - broken
EOF
      cat >"${repo}/addons/broken/scripts/clean.sh" <<EOF
printf "loaded-clean\n"
EOF
      PRODUCTIVE_K3S_ADDONS_REPO_DIR="${repo}"
      PRODUCTIVE_K3S_STACK_NAME=base
      run_stack_addon_clean_hooks'
    The status should equal 1
    The output should include 'loaded-clean'
    The stderr should include "clean hook 'pk3s_addon_clean' is missing"
  End

  It 'fails when stack clean hooks cannot resolve the stack source'
    When run /usr/bin/bash "$RUNNER" "$SCRIPT" '
      repo="$(mktemp -d)"
      mkdir -p "${repo}/addons" "${repo}/stacks"
      PRODUCTIVE_K3S_ADDONS_REPO_DIR="${repo}"
      PRODUCTIVE_K3S_STACK_NAME=missing
      run_stack_addon_clean_hooks'
    The status should equal 1
    The stderr should include "Stack source 'missing' was not found."
  End
End
