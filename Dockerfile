# Dockerfile

FROM alpine

RUN apk add --no-cache bash curl

RUN KUBECTL=$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt) && \
    curl -sLO https://storage.googleapis.com/kubernetes-release/release/${KUBECTL}/bin/linux/amd64/kubectl && \
    chmod +x kubectl && mv kubectl /usr/local/bin/kubectl

ENTRYPOINT ["bash"]
