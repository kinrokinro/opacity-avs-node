FROM gramineproject/gramine:v1.5 as gramine



RUN apt-get update && apt-get install -y --no-install-recommends \
  pkg-config \
  libssl-dev \
  openssl \
  build-essential \
  lld \
  wget

WORKDIR /opacity-avs-node
COPY . .
RUN rm ./bin/avs-cli
RUN rm ./bin/eigenlayer


RUN curl https://sh.rustup.rs -sSf | bash -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
RUN gramine-sgx-gen-private-key

# Install Go
RUN wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
RUN tar -xvf go1.21.0.linux-amd64.tar.gz -C /usr/local
ENV GOROOT=/usr/local/go
ENV GOPATH=$HOME/go
ENV PATH=$GOPATH/bin:$GOROOT/bin:$PATH
RUN go install github.com/Layr-Labs/eigenlayer-cli/cmd/eigenlayer@latest
RUN mv /go/bin/eigenlayer ./bin/
RUN go build -o ./bin/avs-cli cli/main.go
RUN rm go1.21.0.linux-amd64.tar.gz

# This should be associated with an acive IAS SPID in order for
# gramine tools like gramine-sgx-ias-request and gramine-sgx-ias-verify
# ENV RA_CLIENT_SPID=51CAF5A48B450D624AEFE3286D314894
# ENV RA_CLIENT_LINKABLE=1
RUN cargo build --release
RUN make SGX=1
RUN mv ./target/release/opacity-avs-node .
RUN cargo clean

FROM gramineproject/gramine:v1.5 as final
WORKDIR /opacity-avs-node
COPY --from=gramine /opacity-avs-node /opacity-avs-node

RUN apt-get update && apt-get install -y --no-install-recommends \
  openssl \ 
  make

RUN gramine-sgx-gen-private-key
RUN cp /opacity-avs-node/opacity-avs-node /usr/local/bin

LABEL org.opencontainers.image.source=https://github.com/opacitynetwork/opacity-server
LABEL org.opencontainers.image.description="An implementation of the opacity node in Rust."
EXPOSE 7047
CMD ["/opacity-avs-node/start-node.sh"]
