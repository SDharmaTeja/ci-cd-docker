# =============================================================================
# Dockerfile — Demo Spring Boot Application
# Multi-stage build: compile → runtime
# =============================================================================

# ---- Stage 1: Build (Maven) ------------------------------------------------
FROM maven:3.9-eclipse-temurin-17 AS builder

WORKDIR /build

# Copy dependency manifest first (layer-cache friendly)
COPY app/pom.xml .
RUN mvn dependency:go-offline -q

# Copy source and build
COPY app/src ./src
RUN mvn package -DskipTests -q

# ---- Stage 2: Runtime (minimal JRE) ----------------------------------------
FROM eclipse-temurin:17-jre-alpine AS runtime

# Security: run as non-root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy only the JAR
COPY --from=builder /build/target/demo-app-*.jar app.jar

# Build-time metadata labels
ARG APP_VERSION=unknown
ARG BUILD_NUMBER=local
LABEL org.opencontainers.image.title="demo-app" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.description="CI/CD Demo Application" \
      build.number="${BUILD_NUMBER}"

USER appuser

# Expose application port (matches server.port in application.properties)
EXPOSE 3000

# JVM tuning for containers
ENV JAVA_OPTS="-XX:MaxRAMPercentage=75.0 -XX:+UseContainerSupport"

ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]

# Health check (Docker-level)
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/api/health || exit 1
