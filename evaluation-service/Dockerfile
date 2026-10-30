# --- BUILDER STAGE ---
FROM golang:1.21-alpine3.19 AS builder

WORKDIR /src

RUN apk add --no-cache git ca-certificates tzdata

COPY go.mod go.sum* ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w" -o /out/evaluation-service .

# --- RUNTIME STAGE ---
FROM alpine:3.19 AS runtime

RUN apk add --no-cache bash ca-certificates tzdata curl \
    && addgroup -S appgroup \
    && adduser -S appuser -G appgroup

WORKDIR /app
ENV PORT=8004

COPY --from=builder /out/evaluation-service .

USER appuser

EXPOSE 8004

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:${PORT}/health || exit 1

CMD ["./evaluation-service"]
