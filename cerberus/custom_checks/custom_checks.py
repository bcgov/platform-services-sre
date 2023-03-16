import logging
import subprocess
import requests
import json
import cerberus.invoke.command as runcommand

# placeholder for global var
cluster_api_url = "https://10.98.0.1:443"

def check_nodes():
  logging.info("Check if Ready nodes are more than 80 percent of all nodes.")

  # get nodes
  total_node_count = subprocess.check_output("oc get nodes | wc -l", shell=True, universal_newlines=True)
  node_count = subprocess.check_output("oc get nodes | grep Ready | wc -l", shell=True, universal_newlines=True)

  up_ratio = int(node_count)/int(total_node_count)

  return up_ratio > 0.8

def check_cluster_readyz():
  logging.info("Check cluster readyz endpoint.")

  # readyz state
  api_server_readyz_url = cluster_api_url.split(" ")[-1].strip() + "/readyz"
  response = requests.get(api_server_readyz_url, verify=False)

  return "ok" in str(response.content)

def check_image_registry_and_routing():
  logging.info("Check Image Registry API and test on routing layer.")

  # get image_registry URL:
  image_registry_route = runcommand.invoke("oc -n openshift-image-registry get route/public-registry -o json")
  image_registry_host = eval(image_registry_route)['spec']['host']
  image_registry_url = "https://" + image_registry_host + "/healthz"
  logging.info("Detected Image Registry API: " + image_registry_url)

  response = requests.get(image_registry_url, verify=False)


  return response.status_code == 200

def check_storage():
  logging.info("Check if netapp storages are all available.")

  trident_backend_list = runcommand.invoke("oc -n openshift-bcgov-trident get TridentBackends -o json")
  trident_backends = json.loads(trident_backend_list)['items']

  for storage in trident_backends:
    storage_name = storage['metadata']['name']
    logging.info("-> TridentBackends "+ storage_name)

    status_output = runcommand.invoke("oc -n openshift-bcgov-trident get TridentBackends " + storage_name + " -o json")
    status = json.loads(status_output)['state']

    if (status != "online"):
      return False

  return True

def main():
  logging.info("------------------- Start Custom Checks -------------------")

  # get cluster API url:
  global cluster_api_url
  cluster_api_url = runcommand.invoke("kubectl cluster-info | awk 'NR==1' | grep -Eo '(http|https)://[a-zA-Z0-9./?=_%:-]*'")

  check1 = check_nodes()
  check2 = check_cluster_readyz()
  check3 = check_image_registry_and_routing()
  check4 = check_storage()
  logging.info("------------------- Finished Custom Checks -------------------")

  return check1 & check2 & check3 & check4
