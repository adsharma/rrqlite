#!/bin/sh

set -o errexit

cargo build

kill() {
    if [ "$(uname)" = "Darwin" ]; then
        SERVICE='sqlited'
        if pgrep -xq -- "${SERVICE}"; then
            pkill -f "${SERVICE}"
        fi
    else
        set +e # killall will error if finds no process to kill
        killall sqlited
        set -e
    fi
}

rpc() {
    local uri=$1
    local body="$2"

    echo '---'" rpc(:$uri, $body)"

    {
        if [ ".$body" = "." ]; then
            curl --silent "127.0.0.1:$uri"
        else
            curl --silent "127.0.0.1:$uri" -H "Content-Type: application/json" -d "$body"
        fi
    } | {
        if type jq > /dev/null 2>&1; then
            jq
        else
            cat
        fi
    }

    echo
    echo
}

export RUST_LOG=debug 

echo "Killing all running sqlited"

kill

sleep 1

echo "Start 3 uninitialized sqlited servers..."

nohup ./target/debug/sqlited  --node-id 1 --http-addr 127.0.0.1:21001 --single > n1.log &
sleep 1
echo "Server 1 started"

nohup ./target/debug/sqlited  --node-id 2 --http-addr 127.0.0.1:21002 > n2.log &
sleep 1
echo "Server 2 started"

nohup ./target/debug/sqlited  --node-id 3 --http-addr 127.0.0.1:21003 > n3.log &
sleep 1
echo "Server 3 started"
sleep 1

echo "Initialize server 1 as a single-node cluster"
sleep 2
echo
rpc 21001/init '{}'

echo "Server 1 is a leader now"

sleep 2

echo "Get metrics from the leader"
sleep 2
echo
rpc 21001/metrics
sleep 1


echo "Adding node 2 and node 3 as learners, to receive log from leader node 1"

sleep 1
echo
rpc 21001/add-learner       '[2, "127.0.0.1:21002"]'
echo "Node 2 added as learner"
sleep 1
echo
rpc 21001/add-learner       '[3, "127.0.0.1:21003"]'
echo "Node 3 added as learner"
sleep 1

echo "Get metrics from the leader, after adding 2 learners"
sleep 2
echo
rpc 21001/metrics
sleep 1

echo "Changing membership from [1] to 3 nodes cluster: [1, 2, 3]"
echo
rpc 21001/change-membership '[1, 2, 3]'
sleep 1
echo "Membership changed"
sleep 1

echo "Get metrics from the leader again"
sleep 1
echo
rpc 21001/metrics
sleep 1

echo "Write data on leader"
sleep 1
echo
rpc 21001/write '{"Set":{"key":"foo","value":"bar"}}'
sleep 1
echo "Data written"
sleep 1

echo "Read on every node, including the leader"
sleep 1
echo "Read from node 1"
echo
rpc 21001/read  '"foo"'
echo "Read from node 2"
echo
rpc 21002/read  '"foo"'
echo "Read from node 3"
echo
rpc 21003/read  '"foo"'

echo "Killing all nodes in 3s..."
sleep 1
echo "Killing all nodes in 2s..."
sleep 1
echo "Killing all nodes in 1s..."
sleep 1
kill
