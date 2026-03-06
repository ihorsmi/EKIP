FROM python:3.11-slim

# Security: don't run as root in production (we keep root in dev for simplicity of volume mounts)
WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Keep base image lean by default; allow opting in to Agent Framework + MCP deps.
ARG INSTALL_AGENT_FRAMEWORK=false

# System deps for PDF parsing and building wheels
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt requirements-dev.txt requirements-agent-framework.txt /app/

RUN pip install --no-cache-dir -r requirements.txt -r requirements-dev.txt \
    && if [ "$INSTALL_AGENT_FRAMEWORK" = "true" ]; then \
        pip install --no-cache-dir -r requirements-agent-framework.txt; \
    fi

COPY . /app

EXPOSE 8000

# Default command for API container runtime
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
