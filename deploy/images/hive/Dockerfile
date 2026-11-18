ARG HADOOP_IMAGE
FROM ${HADOOP_IMAGE}
ARG HIVE_VERSION
ARG HIVE_DOWNLOAD_URL
ARG MYSQL_CONNECTOR_VERSION
ARG MYSQL_CONNECTOR_DOWNLOAD_URL
USER root
RUN apt-get update && apt-get install -y --no-install-recommends default-mysql-client python3 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fL --retry 3 "${HIVE_DOWNLOAD_URL}" -o /tmp/hive.tar.gz \
    && tar -xzf /tmp/hive.tar.gz -C /opt \
    && mv "/opt/apache-hive-${HIVE_VERSION}-bin" /opt/hive \
    && rm /tmp/hive.tar.gz \
    && rm /opt/hive/lib/guava-*.jar \
    && cp /opt/hadoop/share/hadoop/common/lib/guava-*.jar /opt/hive/lib/ \
    && curl -fL --retry 3 "${MYSQL_CONNECTOR_DOWNLOAD_URL}" \
       -o "/opt/hive/lib/mysql-connector-j-${MYSQL_CONNECTOR_VERSION}.jar" \
    && mkdir -p /opt/hive/runtime-conf \
    && chown -R dp:dp /opt/hive
ENV HIVE_HOME=/opt/hive HIVE_CONF_DIR=/opt/hive/runtime-conf HADOOP_HEAPSIZE=512
ENV PATH="/opt/hive/bin:${PATH}"
COPY entrypoint.sh /usr/local/bin/dp-hive-entrypoint
RUN chmod 755 /usr/local/bin/dp-hive-entrypoint
USER dp
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/dp-hive-entrypoint"]
