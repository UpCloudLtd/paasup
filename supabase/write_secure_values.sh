#!/bin/bash

# Function: write_secure_values
# Usage: write_secure_values "$SECURE_VALUES_FILE"
write_secure_values() {
  local file_path="$1"

  cat > "$file_path" <<EOF
# values.secure.yaml — overrides for rotating Supabase secrets

secret:
    # DATABASE credentials
    db:
        password: "$POSTGRES_PASSWORD"

    # JWT settings (used by GoTrue, PostgREST, Kong, etc.)
    jwt:
        secret:      "$JWT_SECRET"
        anonKey:     "$ANON_KEY"
        serviceKey:  "$SERVICE_ROLE_KEY"
        secretRef:   "" 
        secretRefKey:  
            anonKey:    anonKey
            serviceKey: serviceKey
            secret:     secret

    # DASHBOARD (Studio) credentials
    dashboard:
        username: "$DASHBOARD_USERNAME"
        password: "$DASHBOARD_PASSWORD"

    # S3 credentials for storage object bucket
    s3:
        keyId: "${S3_KEY_ID:-}"
        accessKey: "${S3_ACCESS_KEY:-}"
        secretRef: ""
        secretRefKey:
          keyId: keyId
          accessKey: accessKey

    # SMTP configuration (if your chart references these)
    smtp:
        host:   "${SMTP_HOST:-}"
        port:   "${SMTP_PORT:-}"
        user:   "${SMTP_USER:-}"
        pass:   "${SMTP_PASS:-}"
        sender: "${SMTP_SENDER_NAME:-}"

# POOLER (Supavisor) tenant ID
pooler:
  tenantId: "$POOLER_TENANT_ID"

storage:
  enabled: "$ENABLE_S3"               
  environment:
    STORAGE_BACKEND:            "s3"
    GLOBAL_S3_BUCKET:           "${S3_BUCKET:-}"
    TENANT_ID:                  "supabase"
    GLOBAL_S3_ENDPOINT:         "${S3_ENDPOINT:-}"  
    GLOBAL_S3_PROTOCOL:         "https"  
    GLOBAL_S3_FORCE_PATH_STYLE: "true"  
    AWS_DEFAULT_REGION:         "${S3_REGION:-}" 

# (Any additional secret‐based overrides can go here)
EOF
}
