# Debian 11 is recommended.
FROM python:3.9-slim

# Suppress interactive prompts
ENV DEBIAN_FRONTEND=noninteractive

# (Required) Install utilities required by Spark scripts.
RUN apt update && apt install -y procps tini

WORKDIR /

COPY poetry.lock /poetry.lock
COPY pyproject.toml /pyproject.toml
COPY src/ /src

RUN python3.9 -m pip install --upgrade pip \
    && python3.9 -m pip install poetry==1.1.12
RUN poetry update \
	&& poetry export -f requirements.txt --without-hashes -o requirements.txt \
	&& poetry run pip install . -r requirements.txt -t src_with_deps

# (Optional) Add extra Python modules.
ENV PYTHONPATH=/src_with_deps
RUN mkdir -p "${PYTHONPATH}"

RUN groupadd -g 1099 spark
RUN useradd -u 1099 -g 1099 -d /home/spark -m spark
USER spark