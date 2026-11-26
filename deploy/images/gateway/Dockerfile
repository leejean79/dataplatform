ARG HIVE_IMAGE
FROM ${HIVE_IMAGE}
ARG SPARK_VERSION
ARG SPARK_DOWNLOAD_URL
USER root
RUN curl -fL --retry 3 "${SPARK_DOWNLOAD_URL}" -o /tmp/spark.tgz \
    && tar -xzf /tmp/spark.tgz -C /opt \
    && mv "/opt/spark-${SPARK_VERSION}-bin-hadoop3" /opt/spark \
    && test -f "/opt/spark/jars/spark-sql_2.12-${SPARK_VERSION}.jar" \
    && rm /tmp/spark.tgz \
    && tar -czf /opt/spark/hive-client.tar.gz -C /opt/hive/lib .
ENV SPARK_HOME=/opt/spark PATH="/opt/spark/bin:${PATH}"
# 使用发行包自带的 Scala 编译器构建 SQL 提交入口。Compile with Spark's matching Scala compiler.
COPY OfflineSmoke.scala smoke.sql /opt/spark/smoke/
RUN mkdir /tmp/smoke-classes \
    && java -cp '/opt/spark/jars/*' scala.tools.nsc.Main -usejavacp -d /tmp/smoke-classes /opt/spark/smoke/OfflineSmoke.scala \
    && jar cf /opt/spark/smoke/runner.jar -C /tmp/smoke-classes . -C /opt/spark/smoke smoke.sql \
    && rm -r /tmp/smoke-classes
USER dp
CMD ["gateway"]
