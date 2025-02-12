#!/bin/bash
set -o pipefail
set -eux

# New requirement from ansible-core 2.14
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8

CON_TYPE="${1:-podman}"
SUDO=${ROOT:+"sudo -E"}

ANSIBLECMD=${ANSIBLECMD:-$(command -v ansible-playbook)}
echo "Testing $CON_TYPE connection ${ROOT:+'with root'}"

if [[ "$CON_TYPE" == "podman" ]]; then
    ${SUDO} podman ps | grep -q "${CON_TYPE}-container" || \
        ${SUDO} podman run -d --name "${CON_TYPE}-container" python:3-alpine sleep 1d
elif [[ "$CON_TYPE" == "buildah" ]]; then
    ${SUDO} buildah from --name=buildah-container python:2
fi

pushd "tests/integration/targets/connection_${CON_TYPE}"
ANSIBLECMD=${ANSIBLECMD} SUDO="${SUDO}" ./runme.sh
popd

# Create a big file for uploading to container
[[ ! -f  /tmp/local_file ]] && head -c 5M </dev/urandom >/tmp/local_file

exit_code=0
CMD="${SUDO:-} ${ANSIBLECMD:-ansible-playbook} \
        -i tests/integration/targets/connection_${CON_TYPE}/test_connection.inventory \
        -e connection_type=containers.podman.${CON_TYPE} \
        ci/playbooks/connections/test.yml"
$CMD -vv || exit_code=$?

if [[ "$exit_code" != 0 ]]; then
    $CMD -vvvvv
fi

# Clean up
if [[ "$CON_TYPE" == "podman" ]]; then
    ${SUDO} podman rm -f "${CON_TYPE}-container"
elif [[ "$CON_TYPE" == "buildah" ]]; then
    ${SUDO} buildah rm buildah-container
fi
sudo rm -f /tmp/local_file /tmp/remote_file
