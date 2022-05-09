#!/bin/bash

export SCALA_VERSION=2.13
export KAFKA_VERSION=2.7.0
export ZOOKEEPER_ADDRESS=<ZOOKEEPER_ADDRESS>:2181

set -e

curl https://archive.apache.org/dist/kafka/${KAFKA_VERSION}/kafka_${SCALA_VERSION}-${KAFKA_VERSION}.tgz | tar -zx -C /opt

node_1_response=$(/opt/kafka_2.13-2.7.0/bin/zookeeper-shell.sh $ZOOKEEPER_ADDRESS <<EOF
get /brokers/ids/1
quit
EOF
)

node_2_response=$(/opt/kafka_2.13-2.7.0/bin/zookeeper-shell.sh $ZOOKEEPER_ADDRESS <<EOF
get /brokers/ids/2
quit
EOF
)

node_3_response=$(/opt/kafka_2.13-2.7.0/bin/zookeeper-shell.sh $ZOOKEEPER_ADDRESS <<EOF
get /brokers/ids/3
quit
EOF
)

node_1=$(echo $node_1_response | sed -E 's/[^{]*//;;s/(WATCHER.*)//g')
node_2=$(echo $node_2_response | sed -E 's/[^{]*//;;s/(WATCHER.*)//g')
node_3=$(echo $node_3_response | sed -E 's/[^{]*//;;s/(WATCHER.*)//g')

echo $node_1 | jq
echo $node_2 | jq
echo $node_3 | jq

set +e