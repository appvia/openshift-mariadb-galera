#! /bin/bash

# Copyright 2016 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This script writes out a mysql galera config using a list of newline seperated
# peer DNS names it accepts through stdin.

# /etc/mysql is assumed to be a shared volume so we can modify my.cnf as required
# to keep the config up to date, without wrapping mysqld in a custom pid1.
# The config location is intentionally not /etc/mysql/my.cnf because the
# standard base image clobbers that location.
CFG=/etc/my.cnf.d/galera.cnf

function join {
    local IFS="$1"; shift; echo "$*";
}

HOSTNAME=$(hostname)
# Parse out cluster name, from service name:
CLUSTER_NAME="$(hostname -f | cut -d'.' -f2)"

while read -ra LINE; do
    if [[ "${LINE}" == *"${HOSTNAME}"* ]]; then
        MY_NAME=$LINE
    fi
    PEERS=("${PEERS[@]}" $LINE)
done

if [ "${#PEERS[@]}" = 1 ]; then
    WSREP_CLUSTER_ADDRESS=""
    if [[ "${SAFE_TO_BOOTSTRAP_SINGLE}" == "TRUE" ]]; then
      # Allow the cluster to start if it's been scaled down:
      echo "Allowing bootstrap of single cluster..."
      echo -e "[galera]\nwsrep_new_cluster">/etc/my.cnf.d/recovery.cnf
      sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/g' /var/lib/mysql/grastate.dat
    fi
else
    WSREP_CLUSTER_ADDRESS=$(join , "${PEERS[@]}")
fi
sed -i -e "s|^wsrep_node_address=.*$|wsrep_node_address=${MY_NAME}|" ${CFG}
sed -i -e "s|^wsrep_cluster_name=.*$|wsrep_cluster_name=${CLUSTER_NAME}|" ${CFG}
sed -i -e "s|^wsrep_cluster_address=.*$|wsrep_cluster_address=gcomm://${WSREP_CLUSTER_ADDRESS}|" ${CFG}

# don't need a restart, we're just writing the conf in case there's an
# unexpected restart on the node.
