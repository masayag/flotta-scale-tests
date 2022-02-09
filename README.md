# flotta-scale-tests
The purpose of this project is to test the scalability and performance of [project-flotta](https://github.com/project-flotta/flotta-operator) using [JMeter](https://jmeter.apache.org).

## Running the test plan
Before the test can be run, the test plan needs to be prepared.
The following parameters need to be set in test plan:
* HTTP_SERVER - Yggdrasil Server address
* HTTP_SERVER_PORT - Yggdrasil Server port (default: 8888)
* OCP_API_SERVER - K8S API server address
* OCP_API_PORT - K8S API server port (default: 8443)
* NAMESPACE - Namespaces aren't supported yet, so the test will be run in the default namespace
* DEPLOYMENTS_PER_DEVICE - number of deployments per device (default: 10)* 

The following parameters need to be set via CLI (with -JVAR=VALUE):
* K8S_BEARER_TOKEN - the token is used to access the K8s API (see details below)
* EDGE_DEVICES_COUNT - number of edge devices (default: 10000)
* RAMP_UP_TIME - time to ramp up the number of edge devices in seconds (default: 2000)
* ITERATIONS - number of iterations (default: 180)

After the test plan is prepared, the test can be run:
```bash
K8S_BEARER_TOKEN=<K8s bearer token> # see details below on how to create a privileged token
JVM_ARGS="-Xms1g -Xmx16g -XX:MaxMetaspaceSize=512m" $JMETER_HOME/bin/jmeter.sh -n -t ./test_plans/flotta_test_plan.jmx -l results.csv -e -JK8S_BEARER_TOKEN=$K8S_BEARER_TOKEN
```

## Test Plan
The [basic test plan](./test_plans/flotta_test_plan.jmx) runs the following scenario:
* Register an edge device
* Label the edge device
* Creates 10 edge deployments for the device
* In Loop:
  * Sends heartbeats to the server
  * Get updates from the server

## Creating a token for accessing K8S cluster
For **testing** purposes, we need to create a token for accessing K8S cluster via RESTFUL API.
Once the flotta-operator is deployed on the cluster, the following can be run to create a privileged token:
```bash
# Create a service account
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flotta-scale-test
EOF

# Attach the service account to a privileged role
kubectl create clusterrolebinding flotta-scale-test-cluster-admin --clusterrole=cluster-admin --serviceaccount=default:flotta-scale-test

# Get the token
K8S_BEARER_TOKEN=$(kubectl get secret $(kubectl get serviceaccount flotta-scale-test -o json | jq -r '.secrets[].name') -o yaml | grep " token:" | awk {'print $2'} |  base64 -d)
```
