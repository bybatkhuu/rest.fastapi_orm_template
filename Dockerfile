ARG BASE_IMAGE=debian:11.6-slim
ARG DEBIAN_FRONTEND=noninteractive

ARG APP_DIR="/app/fastapi"
ARG DATA_DIR="/var/lib/fastapi"
ARG LOGS_DIR="/var/log/fastapi"


# Here is the builder image
# hadolint ignore=DL3006
FROM ${BASE_IMAGE} as builder

ARG DEBIAN_FRONTEND

# ARG USE_GPU=false
ARG PYTHON_VERSION=3.9.16

# Set the SHELL to bash with pipefail option
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN _BUILD_TARGET_ARCH=$(uname -m) && \
	echo "BUILDING TARGET ARCHITECTURE: ${_BUILD_TARGET_ARCH}" && \
	rm -rfv /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /root/.cache/* && \
	apt-get clean -y && \
	apt-get update --fix-missing -o Acquire::CompressionTypes::Order::=gz && \
	apt-get install -y --no-install-recommends \
		ca-certificates \
		build-essential \
		wget && \
	if [ "${_BUILD_TARGET_ARCH}" == "x86_64" ]; then \
		export _MINICONDA_URL=https://repo.anaconda.com/miniconda/Miniconda3-py39_23.1.0-1-Linux-x86_64.sh; \
	elif [ "${_BUILD_TARGET_ARCH}" == "aarch64" ]; then \
		export _MINICONDA_URL=https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-aarch64.sh; \
	else \
		echo "Unsupported platform: ${_BUILD_TARGET_ARCH}" && \
		exit 1; \
	fi && \
	wget -nv --show-progress --progress=bar:force:noscroll "${_MINICONDA_URL}" -O /root/miniconda.sh && \
	/bin/bash /root/miniconda.sh -b -p /opt/conda && \
	/opt/conda/condabin/conda clean -y -av && \
	/opt/conda/condabin/conda update -y conda && \
	/opt/conda/condabin/conda install -y python=${PYTHON_VERSION} pip && \
	/opt/conda/bin/pip install --timeout 60 --no-cache-dir --upgrade pip && \
	/opt/conda/bin/pip cache purge && \
	/opt/conda/condabin/conda clean -y -av

COPY ./requirements*.txt /
RUN	_BUILD_TARGET_ARCH=$(uname -m) && \
	# if [ "${_BUILD_TARGET_ARCH}" == "x86_64" ] && [ "${USE_GPU}" == "false" ]; then \
	# 	export _REQUIRE_FILENAME=requirements.amd64.txt; \
	# elif [ "${_BUILD_TARGET_ARCH}" == "x86_64" ] && [ "${USE_GPU}" == "true" ]; then \
	# 	export _REQUIRE_FILENAME=requirements.gpu.txt; \
	# elif [ "${_BUILD_TARGET_ARCH}" == "aarch64" ]; then \
	# 	export _REQUIRE_FILENAME=requirements.arm64.txt; \
	# fi && \
	# < "./${_REQUIRE_FILENAME}" grep -v '^#' | xargs -t -L 1 /opt/conda/bin/pip install --timeout 60 --no-cache-dir && \
	< ./requirements.txt grep -v '^#' | xargs -t -L 1 /opt/conda/bin/pip install --timeout 60 --no-cache-dir && \
	/opt/conda/bin/pip cache purge && \
	/opt/conda/condabin/conda clean -y -av


# Here is the base image
# hadolint ignore=DL3006
FROM ${BASE_IMAGE} as base

ARG DEBIAN_FRONTEND
ARG APP_DIR
ARG DATA_DIR
ARG LOGS_DIR

ARG HASH_PASSWORD="\$1\$K4Iyj0KF\$SyXMbO1NTSeKzng1TBzHt."
ARG UID=1000
ARG GID=11000
ARG USER=fastapi
ARG GROUP=fastapi

ENV UID=${UID} \
	GID=${GID} \
	USER=${USER} \
	GROUP=${GROUP} \
	APP_DIR=${APP_DIR} \
	DATA_DIR=${DATA_DIR} \
	LOGS_DIR=${LOGS_DIR}

ENV	PYTHONIOENCODING=utf-8 \
	PATH=/opt/conda/bin:${PATH}

# Set the SHELL to bash with pipefail option
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Installing system dependencies
# hadolint ignore=DL3008
RUN rm -rfv /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /root/.cache/* && \
	apt-get clean -y && \
	apt-get update --fix-missing -o Acquire::CompressionTypes::Order::=gz && \
	apt-get install -y --no-install-recommends \
		sudo \
		locales \
		tzdata \
		procps \
		iputils-ping \
		net-tools \
		curl \
		nano && \
	apt-get clean -y && \
	sed -i -e 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
	sed -i -e 's/# en_AU.UTF-8 UTF-8/en_AU.UTF-8 UTF-8/' /etc/locale.gen && \
	dpkg-reconfigure --frontend=noninteractive locales && \
	update-locale LANG=en_US.UTF-8 && \
	echo "LANGUAGE=en_US.UTF-8" >> /etc/default/locale && \
	echo "LC_ALL=en_US.UTF-8" >> /etc/default/locale && \
	addgroup --gid ${GID} ${GROUP} && \
	useradd -l -m -d /home/${USER} -s /bin/bash -g ${GROUP} -G sudo -u ${UID} ${USER} && \
	echo "${USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${USER} && \
	chmod 0440 /etc/sudoers.d/${USER} && \
	echo -e "${USER}:${HASH_PASSWORD}" | chpasswd -e && \
	echo -e "\numask 0002" >> /home/${USER}/.bashrc && \
	echo "alias ls='ls -aF --group-directories-first --color=auto'" >> /home/${USER}/.bashrc && \
	echo -e "alias ll='ls -alhF --group-directories-first --color=auto'\n" >> /home/${USER}/.bashrc && \
	echo ". /opt/conda/etc/profile.d/conda.sh" >> /home/${USER}/.bashrc && \
	echo "conda activate base" >> /home/${USER}/.bashrc && \
	mkdir -pv ${APP_DIR} ${DATA_DIR} ${LOGS_DIR} && \
	chown -Rc "${USER}:${GROUP}" ${APP_DIR} ${DATA_DIR} ${LOGS_DIR} && \
	find ${APP_DIR} ${DATA_DIR} -type d -exec chmod -c 770 {} + && \
	find ${APP_DIR} ${DATA_DIR} -type d -exec chmod -c ug+s {} + && \
	find ${LOGS_DIR} -type d -exec chmod -c 775 {} + && \
	find ${LOGS_DIR} -type d -exec chmod -c +s {} + && \
	rm -rfv /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /root/.cache/* /home/${USER}/.cache/*

ENV LANG=en_US.UTF-8 \
	LANGUAGE=en_US.UTF-8 \
	LC_ALL=en_US.UTF-8

COPY --from=builder --chown=${UID}:${GID} /opt /opt


# Here is the production image
# hadolint ignore=DL3006
FROM base as app

WORKDIR ${APP_DIR}
COPY --chown=${UID}:${GID} ./app ${APP_DIR}
COPY --chown=${UID}:${GID} --chmod=770 ./scripts/docker/*.sh /usr/local/bin/

VOLUME ${DATA_DIR}

USER ${UID}:${GID}
ENTRYPOINT ["docker-entrypoint.sh"]
# CMD ["sleep 1 && uvicorn main:app --host=0.0.0.0 --port=${FASTAPI_PORT:-8000} --no-access-log"]
