# Integration harness: build the yup-git binary for Linux, then run it inside a
# Debian image with real `git` installed. yup-git is a thin passthrough that
# forks `git` and forwards every argument verbatim, so the harness asserts
# yup-git's behavior directly against deterministic git operations (init, status,
# hash-object, …) in a throwaway repo with the GIT_* identity/date env pinned.
# Invoked by `make integration`.
FROM golang:1.26 AS build
WORKDIR /src
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /out/yup-git .

FROM debian:stable-slim
RUN apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/yup-git /usr/local/bin/yup-git
COPY integration/run.sh /run.sh
ENTRYPOINT ["/bin/sh", "/run.sh"]
