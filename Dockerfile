# Указываем базовый образ
ARG DOCKER_REGISTRY_URL=library
ARG BASE_IMAGE=debian
ARG BASE_TAG=bullseye-slim

FROM ${DOCKER_REGISTRY_URL}/${BASE_IMAGE}:${BASE_TAG}

# Устанавливаем переменные окружения
ENV LANG="C.UTF-8" \
    LC_ALL="C.UTF-8"

# Устанавливаем необходимые пакеты и gosu
ARG GOSU_VERSION=1.11

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        wget \
        ca-certificates \
        gnupg \
        dirmngr \
        locales \
        iproute2 \
        imagemagick \
        fontconfig \
        p7zip-full \
        procps \
        iproute2; \
    \
    # Установка gosu
    wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-amd64"; \
    chmod +x /usr/local/bin/gosu; \
    gosu nobody true; \
    \
    # Настройка локалей
    localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8; \
    \
    rm -rf /var/lib/apt/lists/* /var/cache/debconf

ENV LANG=ru_RU.UTF-8

# Установка Mono и зависимостей для oscript
ARG MONO_VERSION=6.12.0.122

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ca-certificates \
      gnupg \
      dirmngr \
  && apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF \
  && echo "deb https://download.mono-project.com/repo/debian stable-buster main" > /etc/apt/sources.list.d/mono-official-stable.list \
  && apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
    mono-runtime \
    ca-certificates-mono \
    libmono-i18n4.0-all \
    libmono-system-runtime-serialization4.0-cil \
  && rm -rf /etc/apt/sources.list.d/mono-official-stable.list \
  && apt-get update \
  && cert-sync --user /etc/ssl/certs/ca-certificates.crt \
  && rm -rf \
    /var/lib/apt/lists/* \
    /var/cache/debconf \
    /tmp/*

# Установка oscript
ARG OVM_REPOSITORY_OWNER=oscript-library
ARG OVM_VERSION=v1.2.3
ARG ONESCRIPT_VERSION=stable
ARG ONESCRIPT_PACKAGES="yard"

RUN wget https://github.com/${OVM_REPOSITORY_OWNER}/ovm/releases/download/${OVM_VERSION}/ovm.exe \
  && mv ovm.exe /usr/local/bin/ \
  && echo 'mono /usr/local/bin/ovm.exe "$@"' | tee /usr/local/bin/ovm \
  && chmod +x /usr/local/bin/ovm \
  && ovm use --install ${ONESCRIPT_VERSION}

ENV OSCRIPTBIN=/root/.local/share/ovm/current/bin
ENV PATH="$OSCRIPTBIN:$PATH"

# Установка пакетов oscript
RUN opm install opm \
  && opm update --all \
  && opm install ${ONESCRIPT_PACKAGES}

# Настройка группы и пользователя для 1С
ARG onec_uid="999"
ARG onec_gid="999"

RUN groupadd -r grp1cv8 --gid=$onec_gid \
  && useradd -r -g grp1cv8 --uid=$onec_uid --home-dir=/home/usr1cv8 --shell=/bin/bash usr1cv8 \
  && mkdir -p /var/log/1C /home/usr1cv8/.1cv8/1C/1cv8/conf /opt/1cv8/current/conf \
  && chown -R usr1cv8:grp1cv8 /var/log/1C /home/usr1cv8 \
  && mkdir -p /opt/1cv8 \
  && mkdir -p /var/1C/licenses


# Копируем скрипты и устанавливаем права
COPY scripts/healthcheck.sh /healthcheck.sh
COPY scripts/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
 && chmod +x /healthcheck.sh

# Установка точки входа и команды по умолчанию
ENTRYPOINT ["/entrypoint.sh"]
CMD ["ragent"]
