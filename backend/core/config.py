from __future__ import annotations

from pathlib import Path
from typing import List

from pydantic import AnyUrl, Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application configuration loaded from environment variables.

    - Local development can load environment values from .env.
    - In Azure, use Container Apps environment variables + Key Vault references.

    Adapters are environment-selected so local and Azure providers can be swapped without changing APIs:
      local (disk + Redis + Qdrant) -> Azure (Blob + Service Bus + AI Search)
    is a 1:1 swap with the *same* queue message schema.
    """

    model_config = SettingsConfigDict(env_file=None, extra="ignore")

    # ---- Runtime ----
    ekip_env: str = Field(default="local", alias="EKIP_ENV")  # local|dev|prod
    log_level: str = Field(default="INFO", alias="LOG_LEVEL")

    api_host: str = Field(default="0.0.0.0", alias="API_HOST")
    api_port: int = Field(default=8000, alias="API_PORT")

    allowed_origins: str = Field(default="http://localhost:3000", alias="ALLOWED_ORIGINS")

    data_dir: Path = Field(default=Path("/app/data"), alias="DATA_DIR")
    uploads_dir: Path = Field(default=Path("/app/data/uploads"), alias="UPLOADS_DIR")
    sqlite_path: Path = Field(default=Path("/app/data/ekip.db"), alias="SQLITE_PATH")

    # ---- Provider selection ----
    state_provider: str = Field(default="sqlite", alias="EKIP_STATE_PROVIDER")  # sqlite|cosmos
    # Local defaults keep optional non-Azure development simple.
    queue_provider: str = Field(default="redis", alias="EKIP_QUEUE_PROVIDER")  # redis|servicebus
    storage_provider: str = Field(default="local", alias="EKIP_STORAGE_PROVIDER")  # local|azureblob
    index_provider: str = Field(default="qdrant", alias="EKIP_INDEX_PROVIDER")  # qdrant|azuresearch

    # ---- Local queue + vector defaults (optional) ----
    redis_url: str = Field(default="redis://redis:6379/0", alias="REDIS_URL")
    redis_ingest_queue: str = Field(default="ekip:ingest", alias="REDIS_INGEST_QUEUE")

    qdrant_url: AnyUrl = Field(default="http://qdrant:6333", alias="QDRANT_URL")
    qdrant_collection: str = Field(default="ekip_chunks", alias="QDRANT_COLLECTION")

    # ---- Azure OpenAI (used locally too, if provided) ----
    azure_openai_endpoint: str = Field(default="", alias="AZURE_OPENAI_ENDPOINT")
    azure_openai_api_key: str = Field(default="", alias="AZURE_OPENAI_API_KEY")
    azure_openai_api_version: str = Field(default="2024-10-21", alias="AZURE_OPENAI_API_VERSION")
    azure_openai_chat_deployment: str = Field(default="gpt-4o", alias="AZURE_OPENAI_CHAT_DEPLOYMENT")
    azure_openai_embed_deployment: str = Field(default="text-embedding-3-large", alias="AZURE_OPENAI_EMBED_DEPLOYMENT")

    # ---- Microsoft Foundry / Agent Framework (optional) ----
    azure_ai_project_endpoint: str = Field(default="", alias="AZURE_AI_PROJECT_ENDPOINT")
    azure_openai_responses_deployment_name: str = Field(default="", alias="AZURE_OPENAI_RESPONSES_DEPLOYMENT_NAME")
    azure_mcp_enabled: bool = Field(default=False, alias="AZURE_MCP_ENABLED")
    azure_mcp_server_command: str = Field(default="", alias="AZURE_MCP_SERVER_COMMAND")
    azure_mcp_server_args: str = Field(default="[]", alias="AZURE_MCP_SERVER_ARGS")
    azure_mcp_tool_names: str = Field(default="", alias="AZURE_MCP_TOOL_NAMES")
    azure_mcp_tool_arguments_json: str = Field(default="{}", alias="AZURE_MCP_TOOL_ARGUMENTS_JSON")
    azure_mcp_tool_max_calls: int = Field(default=4, alias="AZURE_MCP_TOOL_MAX_CALLS")
    azure_mcp_tool_timeout_seconds: int = Field(default=30, alias="AZURE_MCP_TOOL_TIMEOUT_SECONDS")

    # ---- Azure Blob Storage (raw documents) ----
    # Prefer Managed Identity in Azure by using account URL; connection string is OK for local dev.
    azure_storage_connection_string: str = Field(default="", alias="AZURE_STORAGE_CONNECTION_STRING")
    azure_storage_account_url: str = Field(default="", alias="AZURE_STORAGE_ACCOUNT_URL")  # https://<acct>.blob.core.windows.net
    azure_storage_container_raw: str = Field(default="raw", alias="AZURE_STORAGE_CONTAINER_RAW")

    # ---- Azure Service Bus (ingestion queue) ----
    azure_servicebus_connection_string: str = Field(default="", alias="AZURE_SERVICEBUS_CONNECTION_STRING")
    azure_servicebus_fqdn: str = Field(default="", alias="AZURE_SERVICEBUS_FQDN")  # <ns>.servicebus.windows.net
    azure_servicebus_queue: str = Field(default="doc-ingest", alias="AZURE_SERVICEBUS_QUEUE")

    # ---- Azure AI Search (hybrid vector + keyword index) ----
    azure_search_endpoint: str = Field(default="", alias="AZURE_SEARCH_ENDPOINT")
    azure_search_admin_key: str = Field(default="", alias="AZURE_SEARCH_ADMIN_KEY")
    azure_search_index_name: str = Field(default="ekip-knowledge", alias="AZURE_SEARCH_INDEX_NAME")
    azure_search_vector_dim: int = Field(default=3072, alias="AZURE_SEARCH_VECTOR_DIM")

    # ---- Azure Cosmos DB (state + audit trail) ----
    azure_cosmos_endpoint: str = Field(default="", alias="AZURE_COSMOS_ENDPOINT")
    azure_cosmos_key: str = Field(default="", alias="AZURE_COSMOS_KEY")
    azure_cosmos_db: str = Field(default="ekip", alias="AZURE_COSMOS_DB")
    azure_cosmos_container_conversations: str = Field(default="conversations", alias="AZURE_COSMOS_CONTAINER_CONVERSATIONS")
    azure_cosmos_container_ingest_jobs: str = Field(default="ingest_jobs", alias="AZURE_COSMOS_CONTAINER_INGEST_JOBS")
    azure_cosmos_container_agent_logs: str = Field(default="agent_logs", alias="AZURE_COSMOS_CONTAINER_AGENT_LOGS")

    # ---- Auth / RBAC ----
    auth_mode: str = Field(default="disabled", alias="AUTH_MODE")  # disabled|dev_token|azure_ad
    dev_auth_token: str = Field(default="dev-token-change-me", alias="DEV_AUTH_TOKEN")
    dev_auth_default_roles: str = Field(default="Admin,Analyst,Viewer", alias="DEV_AUTH_DEFAULT_ROLES")
    azure_tenant_id: str = Field(default="", alias="AZURE_TENANT_ID")
    azure_client_id: str = Field(default="", alias="AZURE_CLIENT_ID")
    azure_ad_audience: str = Field(default="", alias="AZURE_AD_AUDIENCE")

    # ---- Orchestration mode ----
    orchestrator_mode: str = Field(default="deterministic", alias="ORCHESTRATOR_MODE")  # deterministic|maf

    @property
    def allowed_origins_list(self) -> List[str]:
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]

    @property
    def default_dev_roles(self) -> List[str]:
        return [r.strip() for r in self.dev_auth_default_roles.split(",") if r.strip()]

    @property
    def mcp_tool_names_list(self) -> List[str]:
        return [n.strip() for n in self.azure_mcp_tool_names.split(",") if n.strip()]

    @field_validator("log_level")
    @classmethod
    def _normalize_log_level(cls, v: str) -> str:
        return v.upper().strip()

    def ensure_dirs(self) -> None:
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.uploads_dir.mkdir(parents=True, exist_ok=True)


settings = Settings()








