# INTENTIONALLY VULNERABLE
# Scanner testing only. Do NOT deploy.

FROM debian:bullseye-20210902-slim

# Install syft
ARG SYFT_VERSION=v1.45.1
RUN curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh \
  | sh -s -- -b /usr/local/bin ${SYFT_VERSION} \
  && syft version


CMD ["sh"]
