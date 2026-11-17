ARG JDK_IMAGE
FROM ${JDK_IMAGE}
ARG HADOOP_VERSION
ARG HADOOP_DOWNLOAD_URL
USER root
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates procps tini \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fL --retry 3 "${HADOOP_DOWNLOAD_URL}" -o /tmp/hadoop.tar.gz \
    && tar -xzf /tmp/hadoop.tar.gz -C /opt \
    && mv "/opt/hadoop-${HADOOP_VERSION}" /opt/hadoop \
    && rm /tmp/hadoop.tar.gz \
    && groupadd --gid 1000 dp && useradd --uid 1000 --gid dp --create-home dp \
    && mkdir -p /data/hdfs/name /data/hdfs/data /data/yarn/local /data/yarn/logs /opt/hadoop/logs \
    && chown -R dp:dp /data /opt/hadoop
ENV HADOOP_HOME=/opt/hadoop HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop \
    HADOOP_LOG_DIR=/opt/hadoop/logs HADOOP_HEAPSIZE_MAX=512
ENV PATH="/opt/hadoop/bin:/opt/hadoop/sbin:${PATH}"
COPY entrypoint.sh /usr/local/bin/dp-hadoop-entrypoint
RUN chmod 755 /usr/local/bin/dp-hadoop-entrypoint
USER dp
WORKDIR /home/dp
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/dp-hadoop-entrypoint"]
