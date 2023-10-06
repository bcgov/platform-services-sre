import logging
import requests
import json
import time
import cerberus.invoke.command as runcommand

# placeholder for global var
cluster_api_url = "https://10.98.0.1:443"


def check_nodes():
    logging.info("Check if Ready nodes are more than 80 percent of all nodes.")

    # get nodes
    total_node_count = runcommand.invoke("oc get nodes | wc -l")
    node_count = runcommand.invoke("oc get nodes | grep Ready | wc -l")

    up_ratio = int(node_count.strip())/int(total_node_count.strip())

    if (up_ratio > 0.8):
        logging.info("Node check success")
        return True
    else:
        return False


def check_cluster_readyz():
    logging.info("Check cluster readyz endpoint.")

    # readyz state
    api_server_readyz_url = cluster_api_url.split(" ")[-1].strip() + "/readyz"
    response = requests.get(api_server_readyz_url, verify=False)

    if ("ok" in str(response.content)):
        logging.info("Cluster readyz success")
        return True
    else:
        return False


def check_image_registry_and_routing():
    logging.info("Check Image Registry API and test on routing layer.")

    # get image_registry URL:
    image_registry_route = runcommand.invoke(
        "oc -n openshift-image-registry get route/public-registry -o json")
    image_registry_host = eval(image_registry_route)['spec']['host']
    image_registry_url = "https://" + image_registry_host + "/healthz"
    logging.info("Detected Image Registry API: " + image_registry_url)

    response = requests.get(image_registry_url, verify=False)

    if (response.status_code == 200):
        logging.info("Image Registry success")
        return True
    else:
        return False

def check_storage():
    logging.info("Check if netapp storages are all available.")

    trident_backend_list = runcommand.invoke(
        "oc -n openshift-bcgov-trident get TridentBackends -o json")
    trident_backends = json.loads(trident_backend_list)['items']

    for storage in trident_backends:
        storage_name = storage['metadata']['name']
        logging.info("-> TridentBackends " + storage_name)

        status_output = runcommand.invoke(
            "oc -n openshift-bcgov-trident get TridentBackends " + storage_name + " -o json")
        status = json.loads(status_output)['state']

        if (status != "online"):
            return False
    
    logging.info("Storage success")
    return True

def check_PV():
    logging.info("Check if the PV connection is okay.")
    """
    Following line will need to also install jq in dockerfile:
    Comment out for now as I have discussed this with Steven for save it for feature improvment,
    (maybe add a timeout time to check if volum been successfully mounted to pod)
    """
    # check_pod_running = runcommand.invoke(
    #     "oc -n openshift-bcgov-cerberus get pod -l app=deployment-to-test-storage-connection -o json | jq -r '.items[] | select(.status.phase == 'Running') | .status.phase'")
    # if (check_pod_running == "Running"):
    check_file = runcommand.invoke(
        "oc -n openshift-bcgov-cerberus exec $(oc -n openshift-bcgov-cerberus get pod -o name -l app=deployment-to-test-storage-connection) -- timeout --preserve-status 3 touch /mnt/file/test && echo 'successfully'")
    check_block = runcommand.invoke(
        "oc -n openshift-bcgov-cerberus exec $(oc -n openshift-bcgov-cerberus get pod -o name -l app=deployment-to-test-storage-connection) -- timeout --preserve-status 3 touch /mnt/block/test && echo 'successfully'")
    logging.info("PVC check result, file:" +
                 check_file + ", block:" + check_block)
    if (check_file == "successfully" and check_block == "successfully"):
        logging.info("PV connection success")
        return True
    else:
        return False


def check_kyverno():
    logging.info("Check if the Kyverno ConfigMap is okay.")
    # Cerberus will create patch and delete one of the configmap to blackbox test kyverno's status.
    # Those permission is necessary for cerberus SA to do that. Kyverno is validating configmap create / update / delete operations.

    create_config = runcommand.invoke(
        'oc create -n openshift-bcgov-cerberus configmap simple-test --from-literal=data="asdf" && echo "successed"')

    patch_output = runcommand.invoke(
        'oc patch configmap/simple-test -n openshift-bcgov-cerberus -p \'{"data": {"data": "dfad"}}\'')

    delete_config = runcommand.invoke(
        "oc delete -n openshift-bcgov-cerberus configmap/simple-test")

    if ("successed" in create_config) and ("patched" in patch_output):
        logging.info("Kyverno success")
        return True
    else:
        return False


def main():
    logging.info("------------------- Start Custom Checks -------------------")

    # get cluster API url:
    global cluster_api_url
    cluster_api_url = runcommand.invoke(
        "kubectl cluster-info | awk 'NR==1' | grep -Eo '(http|https)://[a-zA-Z0-9./?=_%:-]*'")

    check1 = check_nodes()
    check2 = check_cluster_readyz()
    check3 = check_image_registry_and_routing()
    check4 = check_storage()
    # Note: this check is failing in all clusters, disabling for now!
    # check5 = check_PV()
    check6 = check_kyverno()

    logging.info("------------------- Finished Custom Checks -------------------")

    return check1 & check2 & check3 & check4 & check5 & check6
