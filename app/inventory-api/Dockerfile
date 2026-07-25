FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /inventory-api ./cmd/server/

FROM alpine:3.20
RUN apk add --no-cache ca-certificates
COPY --from=builder /inventory-api /inventory-api
COPY testdata/ /data/
ENV DATA_PATH=/data/products.json
ENV PORT=8081
EXPOSE 8081
ENTRYPOINT ["/inventory-api"]
