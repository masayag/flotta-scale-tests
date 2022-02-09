# flotta-scale-tests
The purpose of this project is to test the scalability and performance of [project-flotta](https://github.com/project-flotta/flotta-operator) using [JMeter](https://jmeter.apache.org).

## Running the test plan
Use [./scripts/run_test_plan.sh](./scripts/run_test_plan.sh) to run the test plan.
The script will create the required resources on the cluster for running the test.

```bash
export KUBECONFIG=path_to_kubeconfig
./scripts/run_test_plan.sh -t ./test_plans/flotta_test_plan.jmx \
                           -n 123 \
                           -d 1 \
                           -i 1 \
                           -p 1 \
                           -r 1 \
                           -s api.devicemgmt3.srv \
                           -g flotta-operator-controller-manager-flotta.apps.devicemgmt3.srv
```

## Test Plans
The [basic test plan](./test_plans/flotta_test_plan.jmx) runs the following scenario:
* For each edge device:
  * Register an edge device
  * Label the edge device
  * Create edge deployments for the device
  * In Loop:
    * Sends heartbeats to the server
    * Get updates from the server
  