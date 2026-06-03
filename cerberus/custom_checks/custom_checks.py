import json
import logging
import time

import requests

import cerberus.invoke.command as runcommand

# Placeholder default; populated by `main()` at runtime.
cluster_api_url = "https://10.98.0.1:443"

HTTP_TIMEOUT_SECONDS = 10
NODE_READY_THRESHOLD = 0.8


def _invoke(command):
    output = runcommand.invoke(command)
    if output is None:
        return ""
    return str(output).strip()


def _outcome(status, reason, details="", target=""):
    return {
        "status": bool(status),
        "reason": reason,
        "details": details,
        "target": target,
    }


def _run_check(name, check_fn):
    start_time = time.monotonic()
    try:
        outcome = check_fn()
        if not isinstance(outcome, dict) or "status" not in outcome or "reason" not in outcome:
            raise ValueError("check must return outcome dict with status and reason")
    except Exception as exc:
        logging.exception("Custom check '%s' raised an exception", name)
        outcome = _outcome(
            False,
            "exception",
            "{}: {}".format(type(exc).__name__, exc),
        )

    duration_ms = int((time.monotonic() - start_time) * 1000)
    result = {
        "name": name,
        "status": bool(outcome.get("status", False)),
        "reason": str(outcome.get("reason", "unknown")),
        "target": str(outcome.get("target", "")),
        "details": str(outcome.get("details", "")),
        "duration_ms": duration_ms,
    }

    status_label = "PASS" if result["status"] else "FAIL"
    logging.info(
        "Custom check result | name=%s | status=%s | reason=%s | target=%s | duration_ms=%s | details=%s",
        result["name"],
        status_label,
        result["reason"],
        result["target"],
        result["duration_ms"],
        result["details"],
    )


    return result


def _request_get(url):
    return requests.get(url, verify=False, timeout=HTTP_TIMEOUT_SECONDS)


def check_nodes():
    logging.info("Check if Ready nodes are at or above %.0f%% of all nodes.", NODE_READY_THRESHOLD * 100)

    nodes_payload = _invoke("oc get nodes -o json")
    if not nodes_payload:
        return _outcome(False, "oc_get_nodes_empty", "oc get nodes returned empty response")

    nodes = json.loads(nodes_payload).get("items", [])
    total_nodes = len(nodes)
    if total_nodes == 0:
        return _outcome(False, "no_nodes_found", "oc get nodes returned zero nodes")

    ready_nodes = 0
    for node in nodes:
        conditions = node.get("status", {}).get("conditions", [])
        is_ready = any(
            condition.get("type") == "Ready" and condition.get("status") == "True"
            for condition in conditions
        )
        if is_ready:
            ready_nodes += 1

    ready_ratio = float(ready_nodes) / float(total_nodes)
    details = "ready_nodes={};total_nodes={};ready_ratio={:.3f};threshold={:.3f}".format(
        ready_nodes,
        total_nodes,
        ready_ratio,
        NODE_READY_THRESHOLD,
    )

    if ready_ratio >= NODE_READY_THRESHOLD:
        return _outcome(True, "ready_ratio_ok", details)
    return _outcome(False, "ready_ratio_below_threshold", details)


def check_cluster_readyz():
    logging.info("Check cluster /readyz endpoint.")

    api_url = cluster_api_url.strip()
    if not api_url:
        return _outcome(False, "cluster_api_url_empty", "cluster API URL is empty")

    readyz_url = api_url.rstrip("/") + "/readyz"

    try:
        response = _request_get(readyz_url)
    except requests.RequestException as exc:
        return _outcome(False, "readyz_request_error", str(exc), readyz_url)

    response_text = response.text.strip()
    if response.status_code == 200 and "ok" in response_text.lower():
        return _outcome(True, "readyz_ok", "status_code={}".format(response.status_code), readyz_url)

    details = "status_code={};body_snippet={}".format(response.status_code, response_text[:200])
    return _outcome(False, "readyz_not_ok", details, readyz_url)


def check_cluster_console():
    logging.info("Check cluster console accessibility.")

    console_url = _invoke("oc whoami --show-console").replace(" ", "")
    if not console_url:
        return _outcome(False, "console_url_empty", "oc whoami --show-console returned empty output")

    if not console_url.startswith("http://") and not console_url.startswith("https://"):
        return _outcome(False, "console_url_invalid", "unexpected console URL: {}".format(console_url), console_url)

    try:
        response = _request_get(console_url)
    except requests.RequestException as exc:
        return _outcome(False, "console_request_error", str(exc), console_url)

    if response.status_code == 200:
        return _outcome(True, "console_http_200", "status_code=200", console_url)

    details = "status_code={};body_snippet={}".format(response.status_code, response.text[:200])
    return _outcome(False, "console_not_200", details, console_url)


def check_image_registry_and_routing():
    logging.info("Check Image Registry API and route health endpoint.")

    route_payload = _invoke("oc -n openshift-image-registry get route/public-registry -o json")
    if not route_payload:
        return _outcome(False, "image_registry_route_empty", "route/public-registry returned empty output")

    route_data = json.loads(route_payload)
    image_registry_host = route_data.get("spec", {}).get("host", "").strip()
    if not image_registry_host:
        return _outcome(False, "image_registry_host_missing", "spec.host missing in public-registry route")

    image_registry_url = "https://{}/healthz".format(image_registry_host)
    logging.info("Detected Image Registry API: %s", image_registry_url)

    try:
        response = _request_get(image_registry_url)
    except requests.RequestException as exc:
        return _outcome(False, "image_registry_request_error", str(exc), image_registry_url)

    if response.status_code == 200:
        return _outcome(True, "image_registry_http_200", "status_code=200", image_registry_url)

    details = "status_code={};body_snippet={}".format(response.status_code, response.text[:200])
    return _outcome(False, "image_registry_not_200", details, image_registry_url)


def check_storage():
    logging.info("Check if Trident backends are all online.")

    trident_payload = _invoke("oc -n openshift-bcgov-trident get TridentBackends -o json")
    if not trident_payload:
        return _outcome(False, "trident_backends_empty", "TridentBackends returned empty output")

    trident_backends = json.loads(trident_payload).get("items", [])
    if not trident_backends:
        return _outcome(False, "trident_backends_not_found", "No TridentBackends discovered")

    failed_backends = []
    for storage in trident_backends:
        storage_name = storage.get("metadata", {}).get("name", "unknown")
        storage_state = storage.get("state")
        if not storage_state:
            storage_state = storage.get("status", {}).get("state", "unknown")

        logging.info("TridentBackend=%s state=%s", storage_name, storage_state)
        if storage_state != "online":
            failed_backends.append("{}:{}".format(storage_name, storage_state))

    if failed_backends:
        return _outcome(
            False,
            "trident_backend_offline",
            "failed_backends={}".format(",".join(failed_backends)),
            "openshift-bcgov-trident/TridentBackends",
        )

    return _outcome(
        True,
        "trident_backends_online",
        "backend_count={}".format(len(trident_backends)),
        "openshift-bcgov-trident/TridentBackends",
    )


def check_PV():
    logging.info("Check if file and block PV mounts are writable.")

    storage_test_pod = _invoke(
        "oc -n openshift-bcgov-cerberus get pod -l app=deployment-to-test-storage-connection "
        "--field-selector=status.phase=Running -o name | head -n 1"
    )

    if not storage_test_pod:
        return _outcome(
            False,
            "pv_test_pod_not_running",
            "No running pod found for app=deployment-to-test-storage-connection",
            "openshift-bcgov-cerberus",
        )

    check_file = _invoke(
        "oc -n openshift-bcgov-cerberus exec {} -- sh -c "
        "'timeout --preserve-status 3 touch /mnt/file/test >/dev/null 2>&1 "
        "&& echo __CERBERUS_PV_OK__ || echo __CERBERUS_PV_FAIL__'".format(storage_test_pod)
    )
    check_block = _invoke(
        "oc -n openshift-bcgov-cerberus exec {} -- sh -c "
        "'timeout --preserve-status 3 touch /mnt/block/test >/dev/null 2>&1 "
        "&& echo __CERBERUS_PV_OK__ || echo __CERBERUS_PV_FAIL__'".format(storage_test_pod)
    )

    details = "pod={};file_result={};block_result={}".format(storage_test_pod, check_file, check_block)

    file_ok = "__CERBERUS_PV_OK__" in check_file
    block_ok = "__CERBERUS_PV_OK__" in check_block
    if file_ok and block_ok:
        return _outcome(True, "pv_file_and_block_writable", details, storage_test_pod)

    return _outcome(False, "pv_write_check_failed", details, storage_test_pod)


def check_kyverno():
    logging.info("Check if Kyverno admission-controller pods are running.")

    running_pod_count_output = _invoke(
        "oc -n kyverno get pods "
        "--selector=app.kubernetes.io/component=admission-controller "
        "--field-selector=status.phase=Running --no-headers | wc -l"
    )

    try:
        running_pod_count = int(running_pod_count_output)
    except ValueError:
        return _outcome(
            False,
            "kyverno_pod_count_parse_error",
            "Unexpected pod count output: {}".format(running_pod_count_output),
            "kyverno",
        )

    if running_pod_count > 0:
        return _outcome(
            True,
            "kyverno_running",
            "running_pod_count={}".format(running_pod_count),
            "kyverno",
        )

    return _outcome(False, "kyverno_no_running_pods", "running_pod_count=0", "kyverno")


def main():
    logging.info("------------------- Start Custom Checks -------------------")

    global cluster_api_url
    cluster_api_url = _invoke(
        "kubectl cluster-info | awk 'NR==1' | grep -Eo '(http|https)://[a-zA-Z0-9./?=_%:-]*'"
    )

    checks = [
        ("nodes", check_nodes),
        ("cluster_readyz", check_cluster_readyz),
        ("cluster_console", check_cluster_console),
        ("image_registry", check_image_registry_and_routing),
        ("storage", check_storage),
        ("pv", check_PV),
        # ("kyverno", check_kyverno),  # TMP: disable until upgrade completes
    ]

    results = []
    for check_name, check_fn in checks:
        results.append(_run_check(check_name, check_fn))

    all_passed = all(result["status"] for result in results)
    failed_results = [result for result in results if not result["status"]]

    if failed_results:
        failed_summary = ",".join(
            "{}:{}".format(result["name"], result["reason"]) for result in failed_results
        )
        logging.warning(
            "Custom checks summary | go_no_go=false | failed_checks=%s",
            failed_summary,
        )
    else:
        logging.info("Custom checks summary | go_no_go=true | failed_checks=none")

    logging.info("------------------- Finished Custom Checks -------------------")
    return all_passed
