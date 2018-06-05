FROM alpine:3.6

MAINTAINER caiqy cqyisbug@163.com

#******************** -Redis-  *********************

RUN apk add --no-cache 'su-exec>=0.2' sed bash ruby

ENV REDIS_VERSION 4.0.8
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz
ENV TIME_ZONE Asiz/Shanghai

# 下载redis 并且编译
RUN set -ex; \
	\
    apk update && apk add --no-cache --virtual .build-deps \
		coreutils \
		gcc \
		linux-headers \
		make \
		musl-dev \
		tzdata \
		tree \
		curl \
		# jq 是用来解析json 的,当然也可以用 grep 和 awk 配合来提取值
		jq \
	; \
	\
	# use host's /etc/localtime
    cp -r -f /usr/share/zoneinfo/Hongkong /etc/localtime ; \
    echo -ne "Alpine Linux 3.6 image. (`uname -rsv`)\n" >> /root/.built ;\
	wget -O redis.tar.gz "$REDIS_DOWNLOAD_URL"; \
	# echo "$REDIS_DOWNLOAD_SHA *redis.tar.gz" | sha256sum -c -; \
	mkdir -p /usr/src/redis; \
	tar -xzf redis.tar.gz -C /usr/src/redis --strip-components=1; \
	rm redis.tar.gz; \
	\
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 1$' /usr/src/redis/src/server.h; \
	sed -ri 's!^(#define CONFIG_DEFAULT_PROTECTED_MODE) 1$!\1 0!' /usr/src/redis/src/server.h; \
	grep -q '^#define CONFIG_DEFAULT_PROTECTED_MODE 0$' /usr/src/redis/src/server.h; \
	\
	make -C /usr/src/redis -j "$(nproc)"; \
	make -C /usr/src/redis install; \
	\
	mkdir -p /home/redis ;\
	mkdir -p /redis/data ;\
	\
	rm -r /usr/src/redis; \
	\
    apk del .build-deps ; \
	apk add --no-cache curl jq 

#  安装ruby环境  由于ruby的原因安装gem install redis的时候会稍微报点错,但是这个错误在docker里面会被捕捉到,所以放到shell 脚本里面去了
#  RUN gem sources --add https://gems.ruby-china.org/ --remove https://rubygems.org/
#  RUN gem install redis -V
#  RUN export PATH="$PATH:/usr/src/redis/src/"

RUN gem sources --add https://gems.ruby-china.org/ --remove https://rubygems.org/;

EXPOSE 6379
EXPOSE 6380
EXPOSE 26379


#******************** -Python-  *********************

# ensure local python is preferred over distribution python
ENV PATH /usr/local/bin:$PATH

# http://bugs.python.org/issue19846
# > At the moment, setting "LANG=C" on a Linux system *fundamentally breaks Python 3*, and that's not OK.
ENV LANG C.UTF-8


# install ca-certificates so that HTTPS works consistently
# the other runtime dependencies for Python are installed later
RUN apk add --no-cache ca-certificates

ENV GPG_KEY C01E1CAD5EA2C4F0B8E3571504C367C218ADD4FF
ENV PYTHON_VERSION 2.7.13

RUN set -ex \
	&& apk add --no-cache --virtual .fetch-deps \
		gnupg \
		libressl \
		tar \
		xz \
	\
	&& wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" \
	&& wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" \
	&& export GNUPGHOME="$(mktemp -d)" \
	&& gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEY" \
	&& gpg --batch --verify python.tar.xz.asc python.tar.xz \
	&& rm -rf "$GNUPGHOME" python.tar.xz.asc \
	&& mkdir -p /usr/src/python \
	&& tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
	&& rm python.tar.xz \
	\
	&& apk add --no-cache --virtual .build-deps  \
		bzip2-dev \
		coreutils \
		dpkg-dev dpkg \
		gcc \
		gdbm-dev \
		libc-dev \
		linux-headers \
		make \
		ncurses-dev \
		libressl \
		libressl-dev \
		pax-utils \
		readline-dev \
		sqlite-dev \
		tcl-dev \
		tk \
		tk-dev \
		zlib-dev \
# add build deps before removing fetch deps in case there's overlap
	&& apk del .fetch-deps \
	\
	&& cd /usr/src/python \
	&& gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)" \
	&& ./configure \
		--build="$gnuArch" \
		--enable-shared \
		--enable-unicode=ucs4 \
	&& make -j "$(nproc)" \
	&& make install \
	\
	&& runDeps="$( \
		scanelf --needed --nobanner --recursive /usr/local \
			| awk '{ gsub(/,/, "\nso:", $2); print "so:" $2 }' \
			| sort -u \
			| xargs -r apk info --installed \
			| sort -u \
	)" \
	&& apk add --virtual .python-rundeps $runDeps \
	&& apk del .build-deps \
	\
	&& find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests \) \) \
			-o \
			\( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \
		\) -exec rm -rf '{}' + \
	&& rm -rf /usr/src/python

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 9.0.1

RUN set -ex; \
	\
	apk add --no-cache --virtual .fetch-deps libressl; \
	\
	wget -O get-pip.py 'https://bootstrap.pypa.io/get-pip.py'; \
	\
	apk del .fetch-deps; \
	\
	python get-pip.py \
		--disable-pip-version-check \
		--no-cache-dir \
		"pip==$PYTHON_PIP_VERSION" \
	; \
	pip --version; \
	\
	find /usr/local -depth \
		\( \
			\( -type d -a \( -name test -o -name tests \) \) \
			-o \
			\( -type f -a \( -name '*.pyc' -o -name '*.pyo' \) \) \
		\) -exec rm -rf '{}' +; \
	rm -f get-pip.py



COPY redis-4.0.1.gem /redis.gem
COPY rdoc-6.0.0.gem /rdoc.gem
COPY logo /redis/data/logo
COPY redis.conf /redis/data/redis.conf
COPY redis-trib.rb /usr/local/bin/redis-trib.rb
COPY logo.sh /logo.sh
RUN chmod +x /logo.sh /usr/local/bin/redis-trib.rb
COPY ep.py /ep.py

CMD [ "/logo.sh" ]
#CMD [ "/ep.py" ]
ENTRYPOINT [ "bash" ,"-c" ]
