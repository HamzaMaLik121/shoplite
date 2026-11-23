# ShopLite inventory: Go, owns the stock table.

FROM golang:1.26-alpine AS build
WORKDIR /src

# go.mod/go.sum first, so a source change doesn't re-download modules.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# Static binary: the runtime image has no libc and no shell.
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/inventory-service .


FROM gcr.io/distroless/static-debian12:nonroot AS runtime

COPY --from=build /out/inventory-service /inventory-service

EXPOSE 8081

# No shell in this image: the binary's -healthcheck mode calls its own /health.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD ["/inventory-service", "-healthcheck"]

ENTRYPOINT ["/inventory-service"]
