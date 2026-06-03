FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends bash \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir openai

COPY review-pr.sh /app/review-pr.sh
RUN chmod +x /app/review-pr.sh

WORKDIR /repo
ENV CI=true

ENTRYPOINT ["/app/review-pr.sh"]
