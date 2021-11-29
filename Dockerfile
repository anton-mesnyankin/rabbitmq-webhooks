FROM elixir:1.10.4 as base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# adds deps for erlang and rabbitmq
RUN apt-get update -yq && \
    apt-get install build-essential rsync zip -yq --no-install-recommends && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# set app basepath
ENV HOME=/opt/

# copy package.json files
COPY . $HOME/rabbitmq-webhooks/

# change workgin dir
WORKDIR $HOME/rabbitmq-webhooks/

# actualize deps build (workaround after switching rabbitmq to monorepo)
RUN git clone https://github.com/rabbitmq/rabbitmq-server && \
    cd rabbitmq-server && git checkout tags/v3.8.26 && \
    make && cd .. && ln -s ./rabbitmq-server/deps

# pulls changes, compile code and build all production stuff
RUN make && make dist DIST_AS_EZS=1

# start new image for lower size
FROM rabbitmq:3.8.26-management-alpine

# change workgin dir
WORKDIR $RABBITMQ_HOME

# copy production complied plugin to the new rabbitmq image
COPY --from=base /opt/rabbitmq-webhooks/plugins/dispcount*.ez plugins
COPY --from=base /opt/rabbitmq-webhooks/plugins/dlhttpc*.ez plugins
COPY --from=base /opt/rabbitmq-webhooks/plugins/rabbitmq_webhooks*.ez plugins

RUN rabbitmq-plugins enable rabbitmq_webhooks
