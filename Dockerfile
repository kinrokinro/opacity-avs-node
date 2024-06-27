# !!! To use this file, please run docker run at the root level of this repository
#
# Using rust:bookworm so that the builder image has OpenSSL 3.0 which is required by async-tungstenite, because
#
# (1) async-tungstenite dynamically links to the OS' OpenSSL by using openssl-sys crate (https://docs.rs/openssl/0.10.56/openssl/#automatic)
#
# (2) async-tungstenite does not utilise the "vendored" feature for its dependency crates, i.e.
# tokio-native-tls, tungstenite and native-tls. The "vendored" feature would have statically linked
# to a OpenSSL copy instead of dynamically link to the OS' OpenSSL (https://docs.rs/openssl/0.10.56/openssl/#vendored)
# — reported an issue here (https://github.com/sdroege/async-tungstenite/issues/119)
#
# (3) We want to use ubuntu:latest (22.04) as the runner image, which (only) has OpenSSL 3.0, because 
# OpenSSL 1.1.1 is reaching EOL in Sept 2023 (https://www.openssl.org/blog/blog/2023/03/28/1.1.1-EOL/)
#
# (4) Therefore, we need the builder image to have the same OpenSSL version, else the built binary will 
# try to dynamically link to a different (non-existing) version in the runner image
#
# (5) rust:latest is still using bullseye somehow which only has OpenSSL 1.1.1
FROM gramineproject/gramine:v1.5 as gramine


# Install pkg-config and libssl-dev for async-tungstenite to use (as explained above)
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
# RUN mkdir ./target
# RUN mkdir ./target/release
# RUN mv ./opacity-avs-node ./target/release

FROM gramineproject/gramine:v1.5 as final
WORKDIR /opacity-avs-node
COPY --from=gramine /opacity-avs-node /opacity-avs-node

RUN apt-get update && apt-get install -y --no-install-recommends \
  openssl \ 
  make

RUN gramine-sgx-gen-private-key
RUN cp /opacity-avs-node/opacity-avs-node /usr/local/bin

# Copy default fixture folder for default usage
# COPY --from=builder /usr/src/opacity-avs-node/fixture ./fixture
# # Copy default config folder for default usage
# COPY --from=builder /usr/src/opacity-avs-node/config ./config
# COPY --from=builder /usr/local/cargo/bin/opacity-avs-node /usr/local/bin/opacity-avs-node
# Label to link this image with the repository in Github Container Registry (https://docs.github.com/en/packages/learn-github-packages/connecting-a-repository-to-a-package#connecting-a-repository-to-a-container-image-using-the-command-line)
LABEL org.opencontainers.image.source=https://github.com/opacitynetwork/opacity-server
LABEL org.opencontainers.image.description="An implementation of the opacity node in Rust."
EXPOSE 7047
CMD ["/opacity-avs-node/start-node.sh"]
