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
      uninstall_k3s
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
End
