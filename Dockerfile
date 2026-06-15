# INTENTIONALLY VULNERABLE
# Scanner testing only. Do NOT deploy.

FROM debian:bullseye-20210902-slim

LABEL purpose="ultra-light-vulnerable-debian11"
LABEL warning="intentionally vulnerable - scanner testing only"

CMD ["sh"]
