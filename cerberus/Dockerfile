# Dockerfile for cerberus

FROM quay.io/openshift/origin-tests:latest as origintests

FROM quay.io/centos/centos:7

MAINTAINER Red Hat OpenShift Performance and Scale

ENV KUBECONFIG /root/.kube/config

# Copy OpenShift CLI, Kubernetes CLI from origin-tests image
COPY --from=origintests /usr/bin/oc /usr/bin/oc
COPY --from=origintests /usr/bin/kubectl /usr/bin/kubectl

# Install dependencies
RUN yum install -y git python39 python3-pip gcc python3-devel zlib-devel libjpeg-devel

RUN git clone https://github.com/redhat-chaos/cerberus.git --branch v1.0.1 /root/cerberus

# to get rid of the need for privileged user:
RUN touch /root/cerberus/cerberus.report && \
    # mkdir /root/cerberus/history && \
    chmod -R 775 /root/cerberus/cerberus.report && \
    chmod -R 775 /root/cerberus/history

# Copy Cerberus custom checks
COPY custom_checks/custom_checks.py /root/cerberus/custom_checks/custom_checks.py
RUN chmod 755 /root/cerberus/custom_checks/custom_checks.py \
    && chgrp 0 /root/cerberus/custom_checks/custom_checks.py

# Copy entrypoint command
COPY entrypoint.sh /usr/local/bin/
RUN chmod 755 /usr/local/bin/entrypoint.sh \
    && chgrp 0 /usr/local/bin/entrypoint.sh

RUN cd /root/cerberus && pip3 install --upgrade pip && pip3 install -r requirements.txt

WORKDIR /root/cerberus

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
