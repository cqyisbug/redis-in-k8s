FROM alpine:3.6

# redis docker images
# author caiqyxyx
# date 2017 12 17

RUN apk add --no-cache 'su-exec>=0.2' sed bash ruby

ENV REDIS_VERSION 4.0.8
ENV REDIS_DOWNLOAD_URL http://download.redis.io/releases/redis-${REDIS_VERSION}.tar.gz
# ENV REDIS_DOWNLOAD_SHA 2049cd6ae9167f258705081a6ef23bb80b7eff9ff3d0d7481e89510f27457591
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
	# 设置时区
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
	mkdir -p /code/redis ;\
	\
#	mv /usr/src/redis/src/redis-trib.rb /code/redis/redis-trib.rb ;\
	\
	rm -r /usr/src/redis; \
	\
    apk del .build-deps ; \
	apk add --no-cache curl jq logrotate 

#  安装ruby环境  由于ruby的原因安装gem install redis的时候会稍微报点错,但是这个错误在docker里面会被捕捉到,所以放到shell 脚本里面去了
#  RUN gem sources --add https://gems.ruby-china.org/ --remove https://rubygems.org/
#  RUN gem install redis -V
#  RUN export PATH="$PATH:/usr/src/redis/src/"

RUN gem sources --add https://gems.ruby-china.org/ --remove https://rubygems.org/;

EXPOSE 6379
EXPOSE 6380
EXPOSE 26379

COPY redis-master.conf /config/redis/master.conf
COPY redis-slave.conf /config/redis/slave.conf
COPY redis-cluster.conf /config/redis/cluster.conf
RUN touch /config/redis/sentinel.conf
COPY entrypoint.sh /code/redis/entrypoint.sh
COPY redis-4.0.1.gem /redis-401.gem
COPY rdoc-6.0.0.gem /rdoc-600.gem
COPY redis-trib.rb /code/redis/redis-trib.rb


RUN chmod +x /code/redis/entrypoint.sh ;\
	chmod +x /code/redis/redis-trib.rb ;\
	cp /code/redis/redis-trib.rb /usr/bin/redis-trib.rb ;\
	chmod +x /usr/bin/redis-trib.rb

CMD [ "/code/redis/entrypoint.sh" ]
ENTRYPOINT [ "bash", "-c" ]
