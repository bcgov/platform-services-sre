# Registry SRE Documentation


registry url: https://registry.developer.gov.bc.ca/
code: https://github.com/bcgov/platform-services-registry-web, https://github.com/bcgov/platform-services-registry-api
structure and workflow diagram: 
* https://app.mural.co/t/platformservices5977/m/platformservices5977/1663353172192/aed6a1cdc30af835988781c2a3b6d0ae6b58ea3c?sender=u19be427953197a3b0b8f3570
* https://app.mural.co/t/platformservices5977/m/platformservices5977/1657826638454/d3f1625dfedb6bf8f8024c44ab088ee1220a7df1?sender=u19be427953197a3b0b8f3570
* https://docs.google.com/document/d/1LbD68TEXdWvRE5iA0nnC81WDjAxJ_uV9KgFgHH5Ba74/edit#heading=h.b88hy0rk86iw
* 
In the ever-evolving landscape of building and delivering software unprecedented system complexity is always one of the challenges. On one side, there's the push for rock-solid reliability, but focusing solely on that might limit your innovation potential. On the flip side, putting all your energy into features without considering stability can lead to risks and tech debts. Striking a balance is the key to delivering fantastic customer experiences.

To find this balance, consider the following:

* **Proactive Remediation**: Stay within error budgets to smartly manage risks, giving your teams a reliability threshold when rolling out new features. By keeping an eye on the error budget and monitoring it over time, you're less likely to run into incidents that leave customers dissatisfied.

* **Accountability**: Bring in Service Level Objectives (SLOs) to create a shared sense of responsibility among your development, operations, and product teams. All parties share the same goal is to keep users happy. This common incentive helps minimize any friction between teams.

* **Focused Action**: SLOs as an early warning system, signaling an impending shift. Armed with this early insight, you can direct and prioritize your efforts where they matter most.

Based off this, we come up with folloing Registry App SRE Implementation


## 1. Realistic SLAs:

- **Uptime SLA:** 99% uptime (allowing 4.4 hours of downtime every three weeks).

- **Response Time SLA:** Responses within 2 seconds.

- **Provision Request SLA:** Completion within an hour for 80% of requests.

- **Success Rate SLA:** At least 99%.
  
## 2. Critical SLIs (Service Level Indicators):

- **Response Time:** Less than 2 seconds.
  
- **Error Rate:** Below 1%.

- **Provision Request Handling Speed:** 80% of requests handled within an hour.



## 3. SLOs (Service Level Objectives):

- **Internal Server Uptime SLO:** 99.2% uptime (maximum 4 hours downtime every three weeks).

- **Response Time SLO:** Less than 8 seconds.

- **Provisioner Handling Time SLO:** 1 hour, triggering an alert if exceeded.

- **SLO Review Frequency:** Every six months.
  

## 4. Balancing Error Budget:

- **Error Budget Definition:** Maintain an error rate below 1%.

- **Feature Development Considerations:** Use release control to bundle feature releases, minimizing the risk of interruptions.


## 5. Monitoring Approaches:

- **Transactional Black Box Tests (uptime.com):** This approach involves checking if the web page successfully loads and pinging an API endpoint that runs a database query. This ensures both the API and database are functioning correctly. Status page [link](https://status.developer.gov.bc.ca/statuspage/platform-service-status-page/1565965), transactional check [link](https://uptime.com/devices/services/1565965)

- **Sysdig Metrics Monitoring:** Utilizes Sysdig to monitor network latency, pod availability, and resource usage. These metrics are crucial when defining the error budget for a given period, providing evidence for performance and reliability.Dashboard link can be found [here](https://app.sysdigcloud.com/#/dashboards/403704?last=9676800&highlightedPanelId=53&scope=kubernetes.cluster.name%20as%20%22cluster%22%20in%20%3F%28%22silver%22%29%20and%20kubernetes.namespace.name%20as%20%22namespace%22%20in%20%3F%28%22101ed4-prod%22%29%20and%20kubernetes.workload.type%20as%20%22type%22%20in%20%3F%20and%20kubernetes.workload.name%20as%20%22workload%22%20in%20%3F%20and%20container.label.io.kubernetes.pod.name%20as%20%22pod%22%20in%20%3F)

PromQL gets used in this implementation are
Pod availability in past 3 weeks
```
100 - sum(avg_over_time( (kube_workload_status_desired{kube_cluster_name='silver', kube_namespace_name='101ed4-prod',kube_workload_name =~ 'platsrv-registry-api|platsrv-registry-web|pltsvc-mongodb'} - kube_workload_status_ready{kube_cluster_name='silver', kube_namespace_name='101ed4-prod', kube_workload_name =~ 'platsrv-registry-api|platsrv-registry-web|pltsvc-mongodb'} > 0 )[3w:]))
```
Network latency in past 3 weeks
```
100 - avg(max_over_time((sysdig_container_net_http_request_time{kube_cluster_name='silver', kube_namespace_name='101ed4-prod',kube_workload_name =~ 'platsrv-registry-api|platsrv-registry-web|pltsvc-mongodb'})[3w:]) / 1000000000 < 2)
```


## Review Frequency:
Regularly review and update this documentation every six months or as needed to ensure alignment with changing conditions and user expectations.