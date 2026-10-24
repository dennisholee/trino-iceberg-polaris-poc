# Kafka Connect image carrying the Apache Iceberg sink connector.
#
# The connector is NOT published as a binary (verified absent from Docker Hub, Maven
# Central, GitHub releases and the Apache dist), so it is BUILT FROM SOURCE here.
# See docs/decisions.md (D13) and poc/tests/RESULTS.md.

# ---------- stage 1: build the connector distribution from the Iceberg source ----------
FROM gradle:8.14.5-jdk21 AS build

ARG ICEBERG_VERSION=1.12.0

USER root
WORKDIR /src

RUN curl -fsSL -o iceberg.tar.gz \
      "https://dlcdn.apache.org/iceberg/apache-iceberg-${ICEBERG_VERSION}/apache-iceberg-${ICEBERG_VERSION}.tar.gz" \
 && tar -xzf iceberg.tar.gz --strip-components=1 \
 && rm iceberg.tar.gz

# Only the kafka-connect runtime module (plus its dependencies) is built.
# Memory is capped: the build host may have limited RAM.
RUN gradle --no-daemon --max-workers=2 \
      -Dorg.gradle.jvmargs="-Xmx2048m -XX:MaxMetaspaceSize=384m" \
      -Dorg.gradle.parallel=false \
      -x test -x integrationTest \
      :iceberg-kafka-connect:iceberg-kafka-connect-runtime:build

RUN cd kafka-connect/kafka-connect-runtime/build/distributions \
 && ls -1 *.zip \
 && ZIP=$(ls -1 *.zip | grep -v hive | head -1) \
 && mkdir -p /tmp/dist /plugin \
 && cd /tmp/dist \
 && jar xf "/src/kafka-connect/kafka-connect-runtime/build/distributions/${ZIP}" \
 && cp -r /tmp/dist/*/lib/. /plugin/ \
 && ls /plugin | head

# ---------- stage 2: Kafka Connect with the connector on the plugin path ----------
# The connector is compiled for Java 17 (Iceberg's baseline), so the worker must run
# Java 17+. cp-kafka-connect 7.x runs Java 11 and fails with UnsupportedClassVersionError.
FROM confluentinc/cp-kafka-connect:8.0.0

# This image's connect-distributed.properties sets plugin.path=/usr/share/java, while the
# CONNECT_PLUGIN_PATH env may take precedence at runtime — install to both so either wins.
COPY --from=build /plugin /usr/share/java/iceberg
COPY --from=build /plugin /opt/kafka/plugins/iceberg

# The connector loads from CONNECT_PLUGIN_PATH=/opt/kafka/plugins (see docker-compose.yml).
# Register the sink after the stack is up:
#   curl -X POST -H "Content-Type: application/json" \
#     --data @../config/kafka-connect/iceberg-sink.json \
#     http://localhost:8083/connectors
