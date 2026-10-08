ARG HAPROXY_VERSION=3.2.25
FROM haproxy:$HAPROXY_VERSION

# Switch to the root user to be able to install packages
USER root

# Update the package list and install redis-tools
# --no-install-recommends keeps the image small
# Then, clean up the apt cache to reduce image size
RUN apt-get update && \
    apt-get install -y --no-install-recommends redis-tools && \
    rm -rf /var/lib/apt/lists/*

# Switch back to the non-root 'haproxy' user for better security. Numeric, so the kubelet
# can verify runAsNonRoot without the pod having to set runAsUser
USER 99:99
