FROM redis:7.2-alpine

# Set environment variables
ENV REDIS_PASSWORD=llm_cache_password

# Create redis directory
RUN mkdir -p /data

# Copy redis configuration
COPY redis.conf /usr/local/etc/redis/redis.conf

# Set permissions
RUN chown -R redis:redis /data /usr/local/etc/redis

# Switch to non-root user (redis user already exists in base image)
USER redis

# Expose port
EXPOSE 6379

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD redis-cli --raw incr ping || exit 1

# Start Redis with configuration
CMD ["redis-server", "/usr/local/etc/redis/redis.conf"]
