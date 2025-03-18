# User Requirements for Service Uptime Status Tool

When looking for an alternative of uptime.com, we look into the following features:
- Status Page
- Notification/alerts
- Service Uptime Checks
- Monitoring Service Hosting
- Access Management

Following are the user requirements gathered from different teams. We will use it for market research.

### Must Haves:
- Status Page:
  - publicly available
  - at least one page per team
- Notification/alerts:
  - define criteria to alert
  - multiple notification channels:
    - email
    - webhook (RC, MSTeams, OpsGenie)
- Service Uptime Checks:
  - ability to setup multiple checks
  - HTTP & API based checks, verify status code and content
  - custom check frequency
- Monitoring Service Hosting:
  - cloud solution, or self hosted but outside of Openshift
  - multiple server locations for redundancy
- Access Management:
  - different teams should have different workspaces


### Nice to Have:
- Status Page:
  - custom URL
  - custom style/layout
  - ability to create multiple pages per team
  - subscription feature (user can subscribe to be notified during ongoing downtime and scheduled maintenance)
  - downtime messages (a place for team to provide more details about ongoing downtime and scheduled maintenance)
- Notification/alerts:
  - Some kind of alert analytics (make it easy to extract downtime outage history)
- Service Uptime Checks:
  - ability to import check history from uptime.com
  - different types of checks in addition to HTTP&API:
    - scripting
    - Transaction checks (e.g.: functional test case that can automate a login by navigating the page)
    - TLS cert check
    - DNS checker (check which DNS our app is being resolved from)
- Monitoring Service Hosting:
  - west canada server location (best within BC)
- Access Management:
  - OAuth integration with keycloak
