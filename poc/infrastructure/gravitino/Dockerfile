# Gravitino + PostgreSQL JDBC driver + POC-only Polaris token validator.
# The upstream image supports optional drivers in /opt/gravitino/jdbc-drivers;
# its entrypoint symlinks postgresql-*.jar into /opt/gravitino/libs.
FROM apache/gravitino:1.3.1 AS validator-build
USER root
COPY auth-validator/src /src
RUN javac -cp "/opt/gravitino/libs/*" -d /classes \
      /src/poc/gravitino/auth/PolarisTokenValidator.java \
    && jar cf /polaris-token-validator.jar -C /classes .

FROM apache/gravitino:1.3.1

USER root
RUN mkdir -p /opt/gravitino/jdbc-drivers

# Remote ADD avoids requiring curl in the base image. Pin the driver version.
ADD https://jdbc.postgresql.org/download/postgresql-42.7.4.jar \
    /opt/gravitino/jdbc-drivers/postgresql-42.7.4.jar

# Spike-only OAuth validator: Polaris JWTs have no `aud` claim, so Gravitino's
# StaticSignKeyValidator cannot be used. This JAR is on the server classpath.
COPY --from=validator-build /polaris-token-validator.jar /opt/gravitino/libs/

RUN chmod 644 /opt/gravitino/jdbc-drivers/postgresql-42.7.4.jar \
    /opt/gravitino/libs/polaris-token-validator.jar

USER 1000
