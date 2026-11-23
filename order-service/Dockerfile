# ShopLite orders: Java 21 + Spring Boot, owns the orders table.

FROM maven:3.9-eclipse-temurin-21 AS build
WORKDIR /src

# pom.xml first, so a source change doesn't re-resolve dependencies.
COPY pom.xml ./
RUN mvn -B -q dependency:go-offline

COPY src ./src
RUN mvn -B -q -DskipTests package


# A jlink runtime contains only the JDK modules this jar needs: ~55 MB instead
# of the ~320 MB the full Temurin JRE image pulls in.
FROM eclipse-temurin:21-jdk-alpine AS jre
# Spring Boot loads classes reflectively, so jdeps can't see everything it needs
# (java.beans, for example, lives in java.desktop). This list is the standard
# Spring Boot set.
RUN jlink \
        --add-modules java.base,java.compiler,java.desktop,java.instrument,java.management,java.naming,java.net.http,java.prefs,java.rmi,java.security.jgss,java.security.sasl,java.sql,java.transaction.xa,java.xml,java.xml.crypto,jdk.crypto.ec,jdk.unsupported,jdk.zipfs \
        --strip-debug --no-man-pages --no-header-files --compress=zip-6 \
        --output /opt/jre


FROM alpine:3.24.4 AS runtime
# Alpine repos keep only current versions; the base image tag is the pin.
# hadolint ignore=DL3018
RUN apk add --no-cache libstdc++ libgcc zlib \
    && addgroup -S app \
    && adduser -S -G app app

WORKDIR /app
COPY --from=jre /opt/jre /opt/jre
COPY --from=build /src/target/order-service.jar /app/order-service.jar

USER app

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD wget -qO- http://127.0.0.1:8082/health || exit 1

ENTRYPOINT ["/opt/jre/bin/java", "-XX:MaxRAMPercentage=75", "-jar", "/app/order-service.jar"]
