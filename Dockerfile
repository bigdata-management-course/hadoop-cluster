# The official apache/hadoop images are amd64-only, so we build a small multi-arch one.
FROM eclipse-temurin:11.0.32_9-jre-jammy

ARG HADOOP_VERSION=3.4.1
ARG HADOOP_SHA512=822cb1531333847e740d942cacf24295a588255786afe11f11c8ff9695be1caae425ddbafd4fda8b0f1fce88336efa05f16d5425659ab225075864ab6b8702bf

# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl python3 procps \
 && rm -rf /var/lib/apt/lists/*

# dlcdn only keeps recent releases; archive.apache.org keeps everything (slower).
# hadolint ignore=DL4006
RUN f=hadoop-${HADOOP_VERSION}-lean.tar.gz \
 && (curl -fsSL -A "Mozilla/5.0" -o /tmp/$f https://dlcdn.apache.org/hadoop/common/hadoop-${HADOOP_VERSION}/$f \
     || curl -fsSL -A "Mozilla/5.0" -o /tmp/$f https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/$f) \
 && echo "${HADOOP_SHA512}  /tmp/$f" | sha512sum -c - \
 && tar -xzf /tmp/$f -C /opt \
 && mv /opt/hadoop-${HADOOP_VERSION} /opt/hadoop \
 && rm -rf /tmp/$f /opt/hadoop/share/doc

ENV HADOOP_HOME=/opt/hadoop \
    HADOOP_CONF_DIR=/opt/hadoop/etc/hadoop \
    PATH=$PATH:/opt/hadoop/bin

# *-site.xml come from ./conf, mounted at /opt/hadoop/etc/lab by docker-compose.
# No native libs are shipped for arm64; silence the "Unable to load native-hadoop" warning on every command.
RUN for f in core hdfs yarn mapred; do ln -sf /opt/hadoop/etc/lab/$f-site.xml $HADOOP_CONF_DIR/$f-site.xml; done \
 && echo 'log4j.logger.org.apache.hadoop.util.NativeCodeLoader=ERROR' >> $HADOOP_CONF_DIR/log4j.properties \
 && useradd -m -s /bin/bash hadoop \
 && mkdir -p /hadoop/dfs /opt/hadoop/logs \
 && chown -R hadoop:hadoop /hadoop /opt/hadoop/logs

# hadolint ignore=DL3066
USER hadoop
WORKDIR /home/hadoop
