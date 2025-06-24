#!/usr/bin/env bash
set -exuo pipefail

# ----------------------------
# Helper: Base64URL encode STDIN
# ----------------------------
if command -v basenc >/dev/null 2>&1; then
  base64url_encode() {
    # Pipiing is because basenc introduce a newline every 64 characters
    basenc --base64url | tr -d '\n' | sed 's/=*$//'
  }
else
  base64url_encode() {
    # Pipiing is because openssl base64 introduce a newline every 64 characters
    openssl base64 | tr -d '\n' | sed 's/+/-/g; s/\//_/g; s/=*$//'
  }
fi

# -------------------------------------------------------------------------------------------------------
# generate_supabase_keys <JWT_SECRET> 
#   - Outputs: ANON_KEY, SERVICE_ROLE_KEY (proper HS256 JWTs for Supabase anon/service roles)
# -------------------------------------------------------------------------------------------------------
generate_supabase_keys() {
  local jwt_secret="$1"
  local now iat exp

  # Compute timestamps: iat = now, exp = now + 10 years (315360000s)
  now=$(date +'%s')
  iat="$now"
  exp=$(( now + 315360000 ))         # 10 years = 315,360,000 seconds

  # Build and Base64URL-encode HEADER: {"alg":"HS256","typ":"JWT"}
  local header_json='{"alg":"HS256","typ":"JWT"}'
  local header_b64
  header_b64=$(printf '%s' "$header_json" | base64url_encode)

  # Build PAYLOAD for anon role
  local payload_anon_json
  payload_anon_json=$(jq -nc --arg role "anon" \
                         --arg iss "supabase" \
                         --argjson iat "$iat" \
                         --argjson exp "$exp" \
                         '{ role: $role, iss: $iss, iat: $iat, exp: $exp }')
  local payload_anon_b64
  payload_anon_b64=$(printf '%s' "$payload_anon_json" | base64url_encode)

  # Build PAYLOAD for service_role
  local payload_service_json
  payload_service_json=$(jq -nc --arg role "service_role" \
                             --arg iss "supabase" \
                             --argjson iat "$iat" \
                             --argjson exp "$exp" \
                             '{ role: $role, iss: $iss, iat: $iat, exp: $exp }')
  local payload_service_b64
  payload_service_b64=$(printf '%s' "$payload_service_json" | base64url_encode)

  # Sign anon: HMACSHA256(header_b64.payload_anon_b64) → base64url(signature)
  local data_anon="${header_b64}.${payload_anon_b64}"
  local sig_anon
  sig_anon=$(printf '%s' "$data_anon" \
                | openssl dgst -sha256 -hmac "$jwt_secret" -binary \
                | base64url_encode)

  # Sign service_role: HMACSHA256(header_b64.payload_service_b64)
  local data_service="${header_b64}.${payload_service_b64}"
  local sig_service
  sig_service=$(printf '%s' "$data_service" \
                  | openssl dgst -sha256 -hmac "$jwt_secret" -binary \
                  | base64url_encode)

  # Remove padding from signatures
  sig_anon="${sig_anon%=}"
  sig_service="${sig_service%=}"

  # Export final `ANON_KEY` and `SERVICE_ROLE_KEY`
  export ANON_KEY="${header_b64}.${payload_anon_b64}.${sig_anon}"
  export SERVICE_ROLE_KEY="${header_b64}.${payload_service_b64}.${sig_service}"
}

# ---------------------------------------------------------
# Example usage:
# ---------------------------------------------------------
# JWT_SECRET="$(openssl rand -hex 20)" 
# generate_supabase_keys "$JWT_SECRET"
# echo "JWT_SECRET=$JWT_SECRET"
# echo "ANON_KEY=$ANON_KEY"
# echo "SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY"
