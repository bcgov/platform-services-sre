![Lifecycle:Maturing](https://img.shields.io/badge/Lifecycle-Maturing-007EC6)

# platform-services-cerberus

Use Cerberus for cluster monitoring that serves a go/no-go signal for uptime status.

### Things that Cerberus monitors:
- [ ] cluster Operators (covered by ops team monitoring)
- [x] critical alerts from prometheus:
  - KubeAPILatencyHigh
  - etcdHighNumberOfLeaderChanges
- [ ] all cluster nodes: master, infra, app (it's a normal operational activity to drain and restart nodes during events like an upgrade, we should only be alerted when there are a significant number of nodes go down at the same time)
- [ ] all pods from the specified namespaces (this is too aggressive as an indicator of cluster uptime status, we are using custom checks instead)
- custom checks are used to monitor the major cluster services identified
  - [x] image registry
  - [x] console and API service
  - [x] worker nodes (when less than 80% is ready)
  - [x] NetApp storage (Trident backend)
  - [x] pvc check (prerequisite: pvc checker deployment managed by CCM)


Here is an example of the monitoring output that reflects the above monitors:
```
10.97.84.1 - - [07/Jul/2021 22:47:28] "GET / HTTP/1.1" 200 -
2021-07-07 22:48:13,528 [INFO] -------------------------- Iteration Stats ---------------------------
2021-07-07 22:48:13,528 [INFO] Time taken to run watch_nodes in iteration 5642: 20.987691402435303 seconds
2021-07-07 22:48:13,528 [INFO] Time taken to run watch_cluster_operators in iteration 5642: 21.139723539352417 seconds
2021-07-07 22:48:13,528 [INFO] Time taken to run watch_namespaces in iteration 5642: 19.242046356201172 seconds
2021-07-07 22:48:13,529 [INFO] Time taken to run sleep_tracker in iteration 5642: 19.27062702178955 seconds
2021-07-07 22:48:13,529 [INFO] Time taken to run entire_iteration in iteration 5642: 81.93008351325989 seconds
2021-07-07 22:48:13,529 [INFO] ----------------------------------------------------------------------

2021-07-07 22:48:34,290 [INFO] Iteration 5643: Node status: True
2021-07-07 22:48:34,362 [INFO] Iteration 5643: Cluster Operator status: True
2021-07-07 22:48:53,600 [INFO] Iteration 5643: openshift-etcd: True
10.97.84.1 - - [07/Jul/2021 22:48:28] "GET / HTTP/1.1" 200 -
2021-07-07 22:48:53,602 [INFO] HTTP requests served: 13152

2021-07-07 22:48:53,602 [INFO] ------------------- Start Custom Checks -------------------
2021-07-07 22:49:12,793 [INFO] Check if Ready nodes are more than 80 percent of all nodes.
2021-07-07 22:49:13,996 [INFO] Check cluster readyz endpoint.
2021-07-07 22:49:14,015 [INFO] Check Image Registry API and test on routing layer.
2021-07-07 22:49:14,562 [INFO] Detected Image Registry API: https://image-registry.apps.silver.devops.gov.bc.ca/healthz
2021-07-07 22:49:15,044 [INFO] Check if netapp storages are all available.
2021-07-07 22:49:15,322 [INFO] -> TridentBackends tbe-7pr79
2021-07-07 22:49:15,611 [INFO] -> TridentBackends tbe-976nm
2021-07-07 22:49:15,926 [INFO] -> TridentBackends tbe-gqf65
2021-07-07 22:49:15,238 [INFO] -> TridentBackends tbe-mwpfn
2021-07-07 22:49:15,517 [INFO] -> TridentBackends tbe-ncvw9
2021-07-07 22:49:15,599 [INFO] ------------------- Finished Custom Checks -------------------

2021-07-07 22:49:15,776 [INFO] Sleeping for the specified duration: 60
```


### Build and Deploy Cerberus

```shell
# expected namespace for cerberus build and deploy to be openshift-bcgov-cerberus
# create a Service Account with custom cluster-reader and rolebinding:
oc -n [namespace] create -f ./devops/cerberus-sa.yml

# get the kube-config locally from the Service Account:
# NOTE: we need the token for kubernetes client.CoreV1Api() authorization
oc -n [namespace] serviceaccounts create-kubeconfig cerberus > config/config

# create configmaps:
oc -n [namespace] create configmap kube-config --from-file=./config/config
oc create configmap cerberus-config --from-file=./config/cerberus-config-template.yaml
# Optional, for local testing only (included in docker image already)
oc create configmap cerberus-custom-check --from-file=./custom_checks/custom_checks.py

# before building, make sure the Artifactory secrets exist:
# push secret:
oc -n [namespace] get secret artifacts-platform-services
# pull secret:
oc -n [namespace] get secret artifacts-platsvcs-reader

# NOTE: the artifactory secrets are shared from `gitops-tools` namespace. If the secrets are missing or not working, copy them from there.

# build:
oc -n [namespace] create -f ./devops/cerberus-bc.yml

# deploy cerberus into a statefulset for HA (make sure it's using the correct image tag):
oc -n [namespace] create -f ./devops/cerberus-sts.yml

# if you just need one pod running, create a deployment instead:
oc -n [namespace] create -f ./devops/cerberus.yml
```

### Get Cerberus Monitoring Result:
```shell
# Poke the exposed endpoint -> should get TRUE
oc -n [namespace] get route cerberus-service
curl -i <cerberus_url>
```

To get the monitoring statistics for a specific period, check it out from a browser with `<cerberus_url>/analyze`.

### Troubleshooting:
```shell
# Prometheus Requests failures:
# 1. get the token from SA (prometheus okay with SA that can list namespaces):
oc -n [namespace] sa get-token cerberus
# 2. then use the token to test query prometheus

# cerberus statistics not returning:
# 1. rsh into pod and check for filesystem permission:
ls -al /root/cerberus/history
```


### Test custom checks:

This document provides instructions on how to test custom checks in the `openshift-bcgov-cerberus` namespace. The recommended approach for testing is to start a debug pod, copy the custom check script to the pod, and run the script from there. The following steps outline the process:
##### Step 1: Start Debug Pod
To begin testing, start a debug pod in the `openshift-bcgov-cerberus` namespace. This can be achieved by executing the following command:
```
oc debug deployment/cerberus-deployment
```

##### Step 2: Copy Custom Check Script
Once the debug pod is running, copy the custom check script (`custom_checks.py`) that you are working on to the debug pod. This can be done using the `oc cp` command. Assuming the custom check script is located at `cerberus/custom_checks/custom_checks.py` and the debug pod is named `cerberus-deployment-debug`, execute the following command:
```
oc cp cerberus/custom_checks/custom_checks.py cerberus-deployment-debug:/root/cerberus/custom_checks/custom_checks.py
```

##### Step 3: Run the Custom Check Script
After copying the custom check script to the debug pod, it's time to run the script using Cerberus. Make sure you are running the script **inside the debug pod**. To run the custom check script, execute the following command:
```
/usr/local/bin/entrypoint.sh
```


By running this command, the custom check script (`custom_check.py`) will be executed within the debug pod.

Once the command is executed, you should see the custom check script being run and the corresponding output or any errors that occur during execution.

This method allows you to test and debug custom checks in a controlled environment before deploying them to production.


### References:
- cerberus source repo: https://github.com/redhat-chaos/cerberus
- setup: https://gexperts.com/wp/building-a-simple-up-down-status-dashboard-for-openshift/
- deploy containerized version: https://github.com/redhat-chaos/cerberus/tree/main/containers
- custom checks: https://github.com/cloud-bulldozer/cerberus#bring-your-own-checks
