#!/bin/bash

usage()
{
cat << EOF
Usage: $0 OPTIONS

This script runs test plan for k4e using jmeter for testing k4e-operator.
OPTIONS:
   -c      Max concurrent reconcilers (default: 3)
   -d      Total of edge devices
   -e      Number of operator's replicas (default: 1)
   -g      Address of HTTP server(as exposed via route or ingress)
   -h      Show this message
   -i      Number of iterations
   -j      Jmeter home directory
   -k      K8s bearer token for accessing OCP API server
   -n      Test run ID
   -p      Total of edge deployments per device
   -r      Ramp-up time in seconds to create all edge devices
   -s      Address of OCP API server
   -t      Test plan file
   -v      Verbose
EOF
}

get_k8s_bearer_token()
{
secrets=$(kubectl get serviceaccount k4e-scale -o json | jq -r '.secrets[].name')
if [[ -z $secrets ]]; then
    echo "INFO: No secrets found for serviceaccount k4e-scale"
    return 1
fi

kubectl get secret $secrets -o json | jq -r '.items[] | select(.type == "kubernetes.io/service-account-token") | .data.token'| base64 -d
}

parse_args()
{
while getopts "c:d:e:g:h:i:j:k:n:p:r:s:t:v" option; do
    case "${option}"
    in
        c) MAX_CONCURRENT_RECONCILES=${OPTARG};;
        d) EDGE_DEVICES_COUNT=${OPTARG};;
        e) REPLICAS=${OPTARG};;
        g) HTTP_SERVER=${OPTARG};;
        i) ITERATIONS=${OPTARG};;
        j) JMETER_HOME=${OPTARG};;
        k) K8S_BEARER_TOKEN=${OPTARG};;
        l) EDGEDEPLOYMENT_CONCURRENCY=${OPTARG};;
        n) TEST_ID=${OPTARG};;
        p) EDGE_DEPLOYMENTS_PER_DEVICE=${OPTARG};;
        r) RAMP_UP_TIME=${OPTARG};;
        s) OCP_API_SERVER=${OPTARG};;
        t) TEST_PLAN=${OPTARG};;
        v) VERBOSE=1;;
        h)
            usage
            exit 0
            ;;
        *)
            usage
            exit 1
            ;;
    esac
done

if [[ -z $MAX_CONCURRENT_RECONCILES ]]; then
    MAX_CONCURRENT_RECONCILES=3
    echo "INFO: Max concurrent reconcilers not specified. Using default value: $MAX_CONCURRENT_RECONCILES"
fi

if [[ -z $REPLICAS ]]; then
    REPLICAS=1
    echo "INFO: Number of replicas not specified. Using default value: $REPLICAS"
fi

if [[ -z $EDGEDEPLOYMENT_CONCURRENCY ]]; then
    EDGEDEPLOYMENT_CONCURRENCY=5
    echo "INFO: Edge deployment concurrency not specified. Using default value: $EDGEDEPLOYMENT_CONCURRENCY"
fi

if [[ -z $TEST_ID ]]; then
    echo "ERROR: Test ID is required"
    usage
    exit 1
fi

if [[ -z $EDGE_DEVICES_COUNT ]]; then
    echo "ERROR: Total of edge devices is required"
    usage
    exit 1
fi

if [[ -z $EDGE_DEPLOYMENTS_PER_DEVICE ]]; then
    echo "ERROR: Edge deployments per device is required"
    usage
    exit 1
fi

if [[ -z $RAMP_UP_TIME ]]; then
    echo "ERROR: Ramp-up time is required"
    usage
    exit 1
fi

if [[ -z $ITERATIONS ]]; then
    echo "ERROR: Iterations is required"
    usage
    exit 1
fi

if [[ -z $OCP_API_SERVER ]]; then
    echo "ERROR: OCP API server is required"
    usage
    exit 1
fi

if [[ -z $K8S_BEARER_TOKEN ]]; then
    echo "INFO: K8s bearer token is not provided. Trying to set it from cluster for k4e-scale service account"
    K8S_BEARER_TOKEN=$( get_k8s_bearer_token )
    if [ "$?" == "1" ]; then
      # Create a service account
      kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: k4e-scale
EOF
      # Attach the service account to a privileged role
      kubectl create clusterrolebinding k4e-scale-cluster-admin --clusterrole=cluster-admin --serviceaccount=default:k4e-scale
      K8S_BEARER_TOKEN=$( get_k8s_bearer_token )
      if [ "$K8S_BEARER_TOKEN" == "" ]; then
        echo "ERROR: Failed to create token for k4e-scale service account"
        exit 1
      fi
    fi
fi

if [[ -z $HTTP_SERVER ]]; then
    echo "ERROR: HTTP server is required"
    usage
    exit 1
fi

if [[ -z $JMETER_HOME ]]; then
    JMETER_HOME=/home/test/apache-jmeter-5.4.1
    echo "INFO: Jmeter home directory is not provided. Using default value: $JMETER_HOME"
fi

if [[ ! -f $TEST_PLAN ]]; then
    echo "ERROR: Test plan is required"
    usage
    exit 1
fi

if [[ -n $VERBOSE ]]; then
    set -xv
fi

test_dir="./test-run-${TEST_ID}"
if [ -d "$test_dir" ]; then
    echo "ERROR: Test directory $test_dir already exists"
    exit 1
fi
}

log_run_details()
{
START_TIME=$SECONDS
echo "INFO: Running test-plan ${TEST_PLAN} as test run ${TEST_ID} with ${EDGE_DEVICES_COUNT} edge devices"
mkdir -p $test_dir/results
touch $test_dir/summary.txt
{
echo "Run by: ${0} with options:"
echo "Jmeter home directory: ${JMETER_HOME}"
echo "Target folder: $test_dir"
echo "Test ID: ${TEST_ID}"
echo "Test plan: ${TEST_PLAN}"
echo "Total of edge devices: ${EDGE_DEVICES_COUNT}"
echo "Edge deployments per device: ${EDGE_DEPLOYMENTS_PER_DEVICE}"
echo "Ramp-up time: ${RAMP_UP_TIME}"
echo "Iterations: ${ITERATIONS}"
echo "OCP API server: ${OCP_API_SERVER}"
echo "K8s bearer token: ${K8S_BEARER_TOKEN}"
echo "HTTP server: ${HTTP_SERVER}"
echo "Replicas: ${REPLICAS}"
echo "Max concurrent reconcilers: ${MAX_CONCURRENT_RECONCILES}"
echo "----------------------------------------------------"
} >> $test_dir/summary.txt

cp $TEST_PLAN $test_dir/
edgedevices=$(oc get edgedevices | wc -l)
edgedeploy=$(oc get edgedeployments | wc -l)
echo "Before test: There are $edgedevices edge devices and $edgedeploy edge deployments" >> $test_dir/summary.txt
}

run_test()
{
echo "INFO: Running test"
JVM_ARGS="-Xms4g -Xmx64g -Xss250k -XX:MaxMetaspaceSize=1g" $JMETER_HOME/bin/jmeter.sh -n -l $test_dir/results.csv \
    -f -e -o $test_dir/results/ -t $TEST_PLAN \
    -JEDGE_DEVICES_COUNT=$EDGE_DEVICES_COUNT \
    -JEDGE_DEPLOYMENTS_PER_DEVICE=$EDGE_DEPLOYMENTS_PER_DEVICE \
    -JRAMP_UP_TIME=$RAMP_UP_TIME \
    -JITERATIONS=$ITERATIONS \
    -JOCP_API_SERVER=$OCP_API_SERVER \
    -JK8S_BEARER_TOKEN=$K8S_BEARER_TOKEN \
    -JHTTP_SERVER=$HTTP_SERVER |& tee -a $test_dir/summary.txt
}

collect_results()
{
echo "INFO: Collecting results"
{
echo "----------------------------------------------------"
echo "After test:" >> $test_dir/summary.txt
} >> $test_dir/summary.txt
edgedevices=$(oc get edgedevices | wc -l)
edgedeploy=$(oc get edgedeployments | wc -l)

echo "After test: There are $edgedevices edge devices and $edgedeploy edge deployments" >> $test_dir/summary.txt
logs_dir=$test_dir/logs
mkdir -p $logs_dir/must-gather

oc adm must-gather --dest-dir=$logs_dir/must-gather 2>/dev/null 1>/dev/null
tar --remove-files -cvzf $logs_dir/must-gather.tar.gz $logs_dir/must-gather 2>/dev/null 1>/dev/null

# Collect additional logs
pods=$(oc get pod -n k4e-operator-system -o name)
for p in $pods
do
  if [[ $p =~ "pod/k4e-operator-controller-manager".* ]]; then
    pod_log=$logs_dir/${p#*/}.log
    oc logs -n k4e-operator-system $p -c manager > $pod_log
    gzip $pod_log
  fi
done

gzip $test_dir/results.csv
ELAPSED_TIME=$(($SECONDS - $START_TIME))
echo "INFO: Test run completed in $((ELAPSED_TIME/60)) min $((ELAPSED_TIME%60)) sec"
}

patch_k4e_operator()
{
echo "INFO: Patching k4e-operator"

kubectl patch cm -n k4e-operator-system k4e-operator-manager-config --type merge --patch '
{ "data": {
    "LOG_LEVEL": "error",
    "OBC_AUTO_CREATE": "false",
     "MAX_CONCURRENT_RECONCILES": "'$MAX_CONCURRENT_RECONCILES'",
     "EDGEDEPLOYMENT_CONCURRENCY": "'$EDGEDEPLOYMENT_CONCURRENCY'"}
}'

memory_per_10k_crs=300
memory_per_workload=$(( 256 + memory_per_10k_crs * ((EDGE_DEVICES_COUNT + EDGE_DEVICES_COUNT * EDGE_DEPLOYMENTS_PER_DEVICE) / 10000) ))
memory_with_spike=$(echo $memory_per_workload*1.25 | bc)
total_memory=${memory_with_spike%.*}Mi

# TODO: if total_cpu is bigger than 10000m, we need to increase the number of replicas
cpu_per_10k_crs=100
total_cpu=$(( 100 + cpu_per_10k_crs * EDGE_DEVICES_COUNT * EDGE_DEPLOYMENTS_PER_DEVICE / 10000 ))m

{
echo "Memory per 10k CRs: $memory_per_10k_crs"
echo "Total memory: $total_memory"
echo "Total CPU: $total_cpu"
echo "----------------------------------------------------"
} >> $test_dir/summary.txt

kubectl patch deployment k4e-operator-controller-manager -n k4e-operator-system -p '
{ "spec": {
    "template": {
      "spec":
        { "containers":
          [{"name": "manager",
            "imagePullPolicy":"Always",
            "resources": {
              "limits": {
                "cpu":"'$total_cpu'",
                "memory":"'$total_memory'"
              }
            }
          }]
        }
      }
    }
}'

kubectl scale --replicas=0 deployment k4e-operator-controller-manager -n k4e-operator-system
kubectl scale --replicas=$REPLICAS deployment k4e-operator-controller-manager -n k4e-operator-system
kubectl wait --for=condition=available -n k4e-operator-system deployment.apps/k4e-operator-controller-manager

count=0

echo "Waiting for HTTP server to be ready at $HTTP_SERVER"
until [[ count -gt 100 ]]
do
  curl -s -i "$HTTP_SERVER" | grep 404 > /dev/null
  if [ "$?" == "1" ]; then
    echo -n "."
    count=$((count+1))
    sleep 5
  else
    echo $'\n'"HTTP server is ready"
    break
  fi
done

if [[ count -gt 100 ]]; then
  echo $'\n'"ERROR: HTTP server is not ready"
  exit 1
fi
}

log_pods_details()
{
{
echo "----------------------------------------------------"
kubectl get pods -n k4e-operator-system -o wide
kubectl top pods -n k4e-operator-system --use-protocol-buffers
} >> $test_dir/summary.txt
}

parse_args "$@"
log_run_details
patch_k4e_operator
log_pods_details
run_test
log_pods_details
collect_results
