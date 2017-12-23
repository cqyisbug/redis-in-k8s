#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM alpine:3.4

# A few problems with compiling Java from source:
#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
#       really hairy.

# Default to UTF-8 file.encoding
ENV LANG C.UTF-8

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
		echo '#!/bin/sh'; \
		echo 'set -e'; \
		echo; \
		echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
	} > /usr/local/bin/docker-java-home \
	&& chmod +x /usr/local/bin/docker-java-home
ENV JAVA_HOME /usr/lib/jvm/java-1.8-openjdk
ENV PATH $PATH:/usr/lib/jvm/java-1.8-openjdk/jre/bin:/usr/lib/jvm/java-1.8-openjdk/bin
ENV CLASSPATH .:$JAVA_HOME/lib:$JAVA_HOME/lib/tools.jar



ENV JAVA_VERSION 8u111
ENV JAVA_ALPINE_VERSION 8.111.14-r0

RUN set -x \
	&& apk add --no-cache \
		openjdk8="$JAVA_ALPINE_VERSION"  \
		bash \
		curl \
	&& [ "$JAVA_HOME" = "$(docker-java-home)" ]

COPY JedisTest.java /java/JedisTest.java
COPY hutool-all-3.2.3.jar /java/hutool-all-3.2.3.jar
COPY jedis-2.9.0.jar /java/jedis-2.9.0.jar
COPY commons-pool2-2.4.2.jar /java/commons-pool2-2.4.2.jar

COPY javac.sh /java/javac.sh

RUN chmod 700 /java/javac.sh

CMD [ "/java/javac.sh" ]
ENTRYPOINT [ "bash", "-c" ]