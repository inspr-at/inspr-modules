#!/usr/bin/env bash
#
# inspr — agent-ready operating layer for builders.
#
# Sub-commands:
#   inspr           = inspr --help (show help)
#   inspr check     = read-only diagnosis (am I onboarded? what drifted?)
#   inspr heal      = diagnose + offer to fix what's fixable
#   inspr onboard   = walk a fresh host through INSPR setup; optionally register
#                     it in Pharos and deploy pharos-beacon
#   inspr post-deploy = prove nixcfg → Pharos → HostDash after deploy
#
# Flags:
#   --help, -h      = show this help
#   --vision        = render VISION.md with Constellation splash
#   --version       = show inspr version
#
# Each sub-command has its own --help (e.g. `inspr check --help`).
#
# Profile auto-detected (workstation = home-manager on PATH; server otherwise).
# Override via $INSPR_DOCTOR_PROFILE env or sub-command --profile flag.
#
# History: this evolved from `inspr-doctor.sh` (a single-purpose diagnostic
# probe) into a fuller CLI per INSPR-195. The check logic is identical
# (34/34 must still pass); heal + onboard modes are NEW additions that
# turn the diagnostic into a self-heal + bootstrap tool.

set -uo pipefail # NOT -e; checks return codes individually

# ── version ────────────────────────────────────────────────────────────────
INSPR_VERSION="2.0.0-dev"

# ── colors ─────────────────────────────────────────────────────────────────
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
DIM=$'\033[2m'
BOLD=$'\033[1m'
RESET=$'\033[0m'

# ── ASCII art ──────────────────────────────────────────────────────────────
# ANSI Shadow — compact header for --help
INSPR_ART_HELP=$(
    cat <<'EOF'
██╗███╗   ██╗███████╗██████╗ ██████╗
██║████╗  ██║██╔════╝██╔══██╗██╔══██╗
██║██╔██╗ ██║███████╗██████╔╝██████╔╝
██║██║╚██╗██║╚════██║██╔═══╝ ██╔══██╗
██║██║ ╚████║███████║██║     ██║  ██║
╚═╝╚═╝  ╚═══╝╚══════╝╚═╝     ╚═╝  ╚═╝
EOF
)

# Constellation — splash for --vision
INSPR_ART_VISION=$(
    cat <<'EOF'
    ·       ✦       .              ✧       ·
        ✧                  ·                       ·
  .       ██╗███╗   ██╗███████╗██████╗ ██████╗      .   ✦
  ✦       ██║████╗  ██║██╔════╝██╔══██╗██╔══██╗  ✧
          ██║██╔██╗ ██║███████╗██████╔╝██████╔╝          ·
    ·     ██║██║╚██╗██║╚════██║██╔═══╝ ██╔══██╗     ·
          ██║██║ ╚████║███████║██║     ██║  ██║           ✧
          ╚═╝╚═╝  ╚═══╝╚══════╝╚═╝     ╚═╝  ╚═╝   .
       ✦        ·            ✧        ·               ✦
              inspiration is the only limit
EOF
)

# ── paths ──────────────────────────────────────────────────────────────────
# All overridable via env vars so consumers without Markus's exact layout
# can still run the tool. Same {VAR:-default} pattern across all four.
HOSTNAME_SHORT="$(hostname -s)"
NIXCFG_DIR="${INSPR_NIXCFG_DIR:-$HOME/Code/nixcfg}"
INSPR_DIR="${INSPR_DIR:-$HOME/Code/inspr}"
FLEETCOM_DIR="${FLEETCOM_DIR:-$HOME/Code/fleetcom}"
SECRETS_DIR="${INSPR_AGENT_SECRETS_DIR:-$HOME/.inspr/secrets/agents}"

# Add nix profile to PATH if missing — agent contexts (SSH, cron, MCP)
# may not inherit the user's interactive PATH. Must precede profile detection.
export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$PATH"

# ── globals ────────────────────────────────────────────────────────────────
# Hoisted to top-level scope so they're visible to all functions (run_check
# reads/writes them from inside _run_all_check_sections). macOS default bash
# 3.2 doesn't support `declare -g`, so we declare here and reset in cmd_*.
PROFILE=""
PASS=0
FAIL=0
SKIP=0
VERBOSE=0
QUIET=0
LIST_ONLY=0
declare -a FAILED_CHECKS=()

# ── helpers ────────────────────────────────────────────────────────────────
section() {
    [[ ${QUIET:-0} -eq 1 ]] && return
    echo ""
    echo "${BOLD}${CYAN}═══ $1 ═══${RESET}"
}

# Render markdown to terminal — try glow, fall back to bat, fall back to cat.
# Used by --vision; could be reused by future commands that show docs.
render_markdown() {
    local md_file="$1"
    [[ -f "$md_file" ]] || {
        echo "${RED}error:${RESET} markdown file not found: $md_file" >&2
        return 1
    }
    if command -v glow >/dev/null 2>&1; then
        glow "$md_file"
    elif command -v bat >/dev/null 2>&1; then
        bat --paging=never --style=plain "$md_file"
    else
        cat "$md_file"
    fi
}

# Detect profile (workstation vs server). Used by `check` mode.
# Auto-detect heuristic: home-manager on PATH = workstation; else = server.
detect_profile() {
    local override="${1:-}"
    if [[ -n "$override" ]]; then
        echo "$override"
    elif [[ -n "${INSPR_DOCTOR_PROFILE:-}" ]]; then
        echo "$INSPR_DOCTOR_PROFILE"
    elif command -v home-manager >/dev/null 2>&1; then
        echo "workstation"
    else
        echo "server"
    fi
}

# run_check <profiles> <slug> <description> <fix-hint>
#   profiles: comma-separated profile list. "any" matches all.
# Calls check_<slug>; prints result; updates counters.
# Reads globals: PROFILE, LIST_ONLY, QUIET, VERBOSE, PASS, FAIL, SKIP, FAILED_CHECKS
run_check() {
    local profiles="$1" slug="$2" desc="$3" hint="$4"
    local fn="check_${slug}"
    local out
    local code

    if [[ ${LIST_ONLY:-0} -eq 1 ]]; then
        printf "  ${DIM}[%-19s]${RESET} %-45s %s\n" "$profiles" "$slug" "$desc"
        return 0
    fi

    if [[ "$profiles" != "any" && ",$profiles," != *",$PROFILE,"* ]]; then
        return 0 # silent skip — doesn't apply to this host class
    fi

    if ! declare -f "$fn" >/dev/null; then
        printf "  ${RED}✗${RESET} %-50s ${DIM}(no check function: $fn)${RESET}\n" "$desc"
        FAIL=$((FAIL + 1))
        FAILED_CHECKS+=("$slug")
        return
    fi

    out="$($fn 2>&1)"
    code=$?

    case $code in
    0)
        [[ ${QUIET:-0} -eq 0 ]] && printf "  ${GREEN}✓${RESET} %s\n" "$desc"
        PASS=$((PASS + 1))
        ;;
    77)
        [[ ${QUIET:-0} -eq 0 ]] && printf "  ${DIM}∘ %s ${YELLOW}[skipped]${RESET}${DIM} %s${RESET}\n" "$desc" "$out"
        SKIP=$((SKIP + 1))
        ;;
    *)
        printf "  ${RED}✗ %s${RESET}\n" "$desc"
        printf "    ${YELLOW}fix:${RESET} %s\n" "$hint"
        if [[ ${VERBOSE:-0} -eq 1 && -n "$out" ]]; then
            echo "$out" | sed 's/^/    '"${DIM}"'│ /;s/$/'"${RESET}"'/'
        fi
        FAIL=$((FAIL + 1))
        FAILED_CHECKS+=("$slug")
        ;;
    esac
}

# ── checks ─────────────────────────────────────────────────────────────────

# ── Toolchain ──
check_nix_on_path() { command -v nix >/dev/null; }
check_home_manager_on_path() { command -v home-manager >/dev/null; }
check_paimos_on_path() { command -v paimos >/dev/null; }
check_devenv_on_path() { command -v devenv >/dev/null; }
check_direnv_on_path() { command -v direnv >/dev/null; }

# ── Network / tailnet ──
check_tailscale_present() {
    command -v tailscale >/dev/null ||
        [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]
}

check_tailscale_up() {
    local ts="tailscale"
    command -v tailscale >/dev/null ||
        ts="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    [[ -x "$ts" || "$ts" == "tailscale" ]] || {
        echo "tailscale binary not found"
        return 77
    }
    "$ts" status >/dev/null 2>&1
}

check_headscale_reachable() {
    # /health is the standard Headscale healthcheck endpoint
    curl -fsS -o /dev/null -m 5 https://hs.barta.cm/health
}

check_tailscale_control_url() {
    # The single biggest gotcha of M5 onboarding day: a host can be up,
    # tailscale logged in, AND the SaaS control server reachable — but
    # pointing at the WRONG control server (Tailscale SaaS, not our
    # self-hosted Headscale). The above two checks both pass in that
    # broken state. This check verifies the tailnet name is hs.barta.cm.
    local ts="tailscale"
    command -v tailscale >/dev/null ||
        ts="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    [[ -x "$ts" || "$ts" == "tailscale" ]] || {
        echo "tailscale binary not found"
        return 77
    }
    command -v jq >/dev/null || {
        echo "jq not on PATH"
        return 77
    }
    local tailnet
    tailnet="$("$ts" status --json 2>/dev/null | jq -r '.CurrentTailnet.Name // empty')"
    [[ "$tailnet" == "hs.barta.cm" ]]
}

# ── SSH ──
check_ssh_host_key() { [[ -f /etc/ssh/ssh_host_ed25519_key ]]; }
check_user_ssh_key() {
    [[ -f "$HOME/.ssh/id_ed25519" || -f "$HOME/.ssh/id_rsa" ]]
}

# ── Secrets pipeline ──
check_agent_secrets_dir() { [[ -d "$SECRETS_DIR" ]]; }

check_agent_secrets_locked() {
    [[ -d "$SECRETS_DIR" ]] || {
        echo "no dir"
        return 77
    }
    local mode
    # GNU stat (-c) first, BSD stat (-f) fallback. Under writeShellApplication's
    # coreutils-on-PATH, BSD `stat -f` is shadowed by GNU's `-f` (= --file-system),
    # which silently returns wrong data. Try GNU first; if not present (raw
    # macOS without coreutils), GNU errors and we fall through to BSD.
    mode=$(stat -c '%a' "$SECRETS_DIR" 2>/dev/null || stat -f '%Mp%Lp' "$SECRETS_DIR" 2>/dev/null)
    [[ "$mode" == "500" || "$mode" == "0500" ]]
}

check_agent_secrets_populated() {
    [[ -d "$SECRETS_DIR" ]] || {
        echo "no dir"
        return 77
    }
    local n
    n=$(find "$SECRETS_DIR" -name '*.env' -type f | wc -l | tr -d ' ')
    [[ "$n" -gt 0 ]]
}

check_host_in_agenix_recipients() {
    [[ -f "$NIXCFG_DIR/secrets/secrets.nix" ]] || {
        echo "no nixcfg checkout at $NIXCFG_DIR"
        return 77
    }
    if grep -qE "^\s*\"?${HOSTNAME_SHORT}\"?\s*=" "$NIXCFG_DIR/secrets/secrets.nix"; then
        return 0
    fi
    if [[ -d "$SECRETS_DIR" ]] && find "$SECRETS_DIR" -name '*.env' -type f 2>/dev/null | grep -q .; then
        echo "host-key not needed (HM agent-secrets via USER key — macOS pattern)"
        return 77
    fi
    return 1
}

# ── Identity / auth ──
check_no_legacy_gitconfig() {
    # ~/.gitconfig silently overrides ~/.config/git/config (HM XDG location).
    [[ ! -f ~/.gitconfig ]]
}

check_git_identity_personal_default() {
    local tmp
    tmp=$(mktemp -d) || return 1
    (
        cd "$tmp" && git init -q
        local email
        email=$(git config user.email 2>/dev/null)
        [[ "$email" == "markus@barta.com" ]]
    )
    local rc=$?
    rm -rf "$tmp"
    return "$rc"
}

check_gh_auth() {
    command -v gh >/dev/null || {
        echo "gh not on PATH"
        return 77
    }
    (
        if [[ -f "$SECRETS_DIR/GH_TOKEN.env" ]]; then
            set -a
            # shellcheck disable=SC1090
            source "$SECRETS_DIR/GH_TOKEN.env"
            set +a
        fi
        if [[ -z "${GH_TOKEN:-}" ]] && ! gh auth status -h github.com >/dev/null 2>&1; then
            echo "no GH_TOKEN.env on this host AND no gh-cli OAuth login configured"
            return 77
        fi
        gh api user >/dev/null 2>&1
    )
}

check_paimos_auth() {
    command -v paimos >/dev/null || {
        echo "paimos not on PATH"
        return 77
    }
    # Prove instance-config + keyring auth specifically: ambient compatibility
    # overrides must not make this workstation check pass. Authentication is
    # established explicitly with the hidden prompt from `paimos auth login`.
    (
        unset PAIMOS_URL PAIMOS_API_KEY PPM_URL PPMAPIKEY
        paimos auth whoami >/dev/null 2>&1
    )
}

check_paimos_instance_config() {
    local f="$HOME/.paimos/config.yaml"
    [[ -f "$f" ]] || return 1
    local mode
    # GNU stat first, BSD fallback (see check_agent_secrets_locked comment).
    mode=$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Mp%Lp' "$f" 2>/dev/null)
    [[ "$mode" == "600" || "$mode" == "0600" ]] || return 1

    # Fail closed and silently: yq emits only a boolean, and its diagnostics
    # stay suppressed so malformed YAML cannot expose configuration content.
    command -v yq >/dev/null || return 1
    local legacy_api_key_present
    if ! legacy_api_key_present="$(yq -r '[.. | select(tag == "!!map") | has("api_key")] | any' "$f" 2>/dev/null)"; then
        return 1
    fi
    if [[ "$legacy_api_key_present" == "true" ]]; then
        echo "$f contains forbidden legacy api_key field"
        return 1
    fi
    [[ "$legacy_api_key_present" == "false" ]]
}

# ── Drift ──
check_nixcfg_envrc_canonical_path() {
    local envrc="$NIXCFG_DIR/.envrc"
    [[ -f "$envrc" ]] || {
        echo "no .envrc at $envrc"
        return 77
    }
    grep -q '\.inspr/secrets/agents' "$envrc"
}

check_nixcfg_envrc_content_filter() {
    local envrc="$NIXCFG_DIR/.envrc"
    [[ -f "$envrc" ]] || {
        echo "no .envrc at $envrc"
        return 77
    }
    grep -qF '[A-Z_][A-Z0-9_]*=' "$envrc"
}

check_secrets_audit_clean() {
    if command -v secrets-audit >/dev/null; then
        secrets-audit --quiet >/dev/null 2>&1
        return $?
    fi
    local script="$NIXCFG_DIR/scripts/secrets-audit.sh"
    [[ -x "$script" ]] || {
        echo "neither secrets-audit on PATH nor nixcfg local copy"
        return 77
    }
    "$script" --quiet >/dev/null 2>&1
}

# ── repos ──
check_repo_nixcfg() { [[ -d "$NIXCFG_DIR/.git" ]]; }
check_repo_inspr() { [[ -d "$INSPR_DIR/.git" ]]; }
check_repo_fleetcom() { [[ -d "$FLEETCOM_DIR/.git" ]]; }

# ── doctrine (Phase 6, INSPR-187) ──
_doctrine_kernel_present() {
    local repo_dir="$1"
    [[ -f "$repo_dir/doctrine/docs/AGENTS-KERNEL.md" ]]
}

_doctrine_claude_md_loader() {
    local repo_dir="$1"
    local claude_md="$repo_dir/CLAUDE.md"
    [[ -f "$claude_md" ]] || {
        echo "$claude_md missing"
        return 1
    }
    grep -qF '@./doctrine/docs/AGENTS-KERNEL.md' "$claude_md" || {
        echo "CLAUDE.md does not @-ref AGENTS-KERNEL.md (post-Phase-6 loader)"
        return 1
    }
    if grep -qE '@\./doctrine/docs/AGENTS-(CORE|PROFILE-MARKUS)\.md' "$claude_md"; then
        echo "CLAUDE.md still @-refs legacy CORE/PROFILE-MARKUS — re-introduces >40k warning"
        return 1
    fi
    return 0
}

check_doctrine_nixcfg_kernel_present() { _doctrine_kernel_present "$NIXCFG_DIR"; }
check_doctrine_inspr_kernel_present() { _doctrine_kernel_present "$INSPR_DIR"; }
check_doctrine_fleetcom_kernel_present() { _doctrine_kernel_present "$FLEETCOM_DIR"; }

check_doctrine_nixcfg_claude_md_loader() { _doctrine_claude_md_loader "$NIXCFG_DIR"; }
check_doctrine_inspr_claude_md_loader() { _doctrine_claude_md_loader "$INSPR_DIR"; }
check_doctrine_fleetcom_claude_md_loader() { _doctrine_claude_md_loader "$FLEETCOM_DIR"; }

check_doctrine_kernel_size_budget() {
    local kernel="$NIXCFG_DIR/doctrine/docs/AGENTS-KERNEL.md"
    [[ -f "$kernel" ]] || {
        echo "kernel not present (submodule not initialized?)"
        return 77
    }
    local size
    size=$(wc -c <"$kernel" | tr -d ' ')
    if [[ $size -gt 12000 ]]; then
        echo "kernel is $size bytes, exceeds 12000 hard budget"
        return 1
    fi
    return 0
}

# ── Server-profile checks ──
check_system_agenix_decrypted() {
    [[ -d /run/agenix ]]
}

# ── INSPR suite post-deploy validation (INSPR-215) ─────────────────────────
post_pass() {
    printf "  ${GREEN}✓${RESET} %s\n" "$1"
    POST_PASS=$((POST_PASS + 1))
}

post_fail() {
    printf "  ${RED}✗ %s${RESET}\n" "$1"
    printf "    ${YELLOW}owner:${RESET} %s\n" "$2"
    POST_FAIL=$((POST_FAIL + 1))
}

post_skip() {
    printf "  ${DIM}∘ %s ${YELLOW}[skipped]${RESET}${DIM} %s${RESET}\n" "$1" "$2"
    POST_SKIP=$((POST_SKIP + 1))
}

post_check_json() {
    local label="$1" owner="$2" file="$3"
    shift 3
    if jq -e "$@" "$file" >/dev/null 2>&1; then
        post_pass "$label"
    else
        post_fail "$label" "$owner"
    fi
}

post_context_keys() {
    case "$1" in
    lan) echo "lanHostname lanIp" ;;
    tailnet) echo "tailnet" ;;
    both) echo "lanHostname lanIp tailnet" ;;
    esac
}

# ── Pharos onboarding helpers (PHAROS-7) ───────────────────────────────────
pharos_default_role() {
    case "${PROFILE:-}" in
    workstation) echo "workstation" ;;
    *) echo "server" ;;
    esac
}

pharos_default_is_nix() {
    if [[ -f /etc/NIXOS ]]; then
        echo "true"
    else
        echo "false"
    fi
}

pharos_validate_host() {
    [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]
}

pharos_validate_interval() {
    [[ "$1" =~ ^[0-9]+$ ]] && [[ "$1" -gt 0 ]]
}

pharos_beacon_deployed() {
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet pharos-beacon 2>/dev/null; then
        return 0
    fi
    if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -Fxq pharos-beacon; then
        return 0
    fi
    return 1
}

pharos_step_status() {
    local token_out="$1"
    local token_present=1
    local deployed_present=1
    [[ -f "$token_out" ]] && token_present=0
    pharos_beacon_deployed && deployed_present=0

    if [[ $token_present -eq 0 && $deployed_present -eq 0 ]]; then
        echo "ok"
    elif [[ $token_present -eq 0 || $deployed_present -eq 0 ]]; then
        echo "partial"
    else
        echo "missing"
    fi
}

pharos_register_host() {
    local pharos_url="$1" host="$2" role="$3" is_nix="$4" interval="$5" token_out="$6"
    local bootstrap="${INSPR_PHAROS_REGISTRATION_TOKEN:-${PHAROS_REGISTRATION_TOKEN:-}}"
    local tmpdir payload response http_code curl_status token token_dir msg

    if [[ -z "$bootstrap" ]]; then
        echo "${RED}error:${RESET} set INSPR_PHAROS_REGISTRATION_TOKEN before --pharos-register" >&2
        return 2
    fi
    if [[ -e "$token_out" ]]; then
        echo "${RED}error:${RESET} token file already exists: $token_out" >&2
        echo "       refusing to rotate/overwrite a raw beacon token implicitly" >&2
        return 2
    fi
    token_dir="$(dirname "$token_out")"
    if [[ ! -d "$token_dir" ]]; then
        mkdir -p "$token_dir" || return 1
        chmod 700 "$token_dir" 2>/dev/null || true
    fi
    if [[ ! -w "$token_dir" ]]; then
        echo "${RED}error:${RESET} token directory is not writable: $token_dir" >&2
        return 2
    fi
    command -v jq >/dev/null 2>&1 || {
        echo "${RED}error:${RESET} jq is required for Pharos registration" >&2
        return 2
    }
    command -v curl >/dev/null 2>&1 || {
        echo "${RED}error:${RESET} curl is required for Pharos registration" >&2
        return 2
    }

    tmpdir="$(mktemp -d)" || return 2
    payload="$tmpdir/register.json"
    response="$tmpdir/response.json"
    chmod 700 "$tmpdir"

    jq -n \
        --arg name "$host" \
        --arg role "$role" \
        --argjson is_nix "$is_nix" \
        --argjson heartbeat_interval_secs "$interval" \
        '{name:$name, role:$role, is_nix:$is_nix, heartbeat_interval_secs:$heartbeat_interval_secs}' \
        >"$payload" || {
        rm -rf "$tmpdir"
        return 2
    }

    http_code="$(
        curl -sS -m 15 \
            -o "$response" \
            -w '%{http_code}' \
            -H "Content-Type: application/json" \
            --config - \
            --data-binary "@$payload" \
            "$pharos_url/register" <<CURLCFG
header = "Authorization: Bearer ${bootstrap}"
CURLCFG
    )"
    curl_status=$?
    if [[ $curl_status -ne 0 ]]; then
        echo "${RED}error:${RESET} Pharos registration request failed" >&2
        rm -rf "$tmpdir"
        return 1
    fi
    if [[ "$http_code" != "201" ]]; then
        msg="$(jq -r '.error // "unexpected response"' "$response" 2>/dev/null || echo "unexpected response")"
        echo "${RED}error:${RESET} Pharos registration failed (HTTP $http_code): $msg" >&2
        rm -rf "$tmpdir"
        return 1
    fi

    token="$(jq -r --arg host "$host" 'select(.name == $host) | .token // empty' "$response" 2>/dev/null)"
    if [[ -z "$token" || "$token" == *$'\n'* || "$token" == *$'\r'* ]]; then
        echo "${RED}error:${RESET} Pharos registration response did not contain a usable token" >&2
        rm -rf "$tmpdir"
        return 1
    fi

    (
        umask 077
        printf 'PHAROS_TOKEN=%s\n' "$token" >"$token_out"
    ) || {
        rm -rf "$tmpdir"
        return 1
    }
    chmod 600 "$token_out" 2>/dev/null || true

    rm -rf "$tmpdir"
    printf "  ${GREEN}✓${RESET} Pharos registered ${CYAN}%s${RESET}; beacon token stored at ${CYAN}%s${RESET}\n" "$host" "$token_out"
}

pharos_deploy_beacon_docker() {
    local pharos_url="$1" host="$2" role="$3" is_nix="$4" interval="$5" token_out="$6" image="$7"
    local -a args

    command -v docker >/dev/null 2>&1 || {
        echo "${RED}error:${RESET} docker is required for --pharos-deploy=docker" >&2
        return 2
    }
    [[ -f "$token_out" ]] || {
        echo "${RED}error:${RESET} token file not present: $token_out" >&2
        return 2
    }
    docker info >/dev/null 2>&1 || {
        echo "${RED}error:${RESET} docker daemon is not reachable" >&2
        return 1
    }

    if docker ps -a --format '{{.Names}}' 2>/dev/null | grep -Fxq pharos-beacon; then
        echo "  ${DIM}Replacing existing local pharos-beacon container...${RESET}"
        docker rm -f pharos-beacon >/dev/null || return 1
    fi

    args=(
        run -d
        --name pharos-beacon
        --restart unless-stopped
        --network host
        --user "$(id -u):$(id -g)"
        --env-file "$token_out"
        -e "PHAROS_URL=$pharos_url"
        -e "PHAROS_INTERVAL=$interval"
        -e "PHAROS_HOSTNAME=$host"
        -e "PHAROS_ROLE=$role"
        --entrypoint /usr/local/bin/pharos-beacon
    )
    if [[ "$is_nix" == "true" ]]; then
        if [[ -d "$NIXCFG_DIR" ]]; then
            args+=(
                -e NIXCFG_DIR=/nixcfg
                -e GIT_CONFIG_COUNT=1
                -e GIT_CONFIG_KEY_0=safe.directory
                -e GIT_CONFIG_VALUE_0=/nixcfg
                -v "$NIXCFG_DIR:/nixcfg:ro"
            )
        else
            echo "  ${YELLOW}warning:${RESET} Nix host but nixcfg checkout not found; freshness will be best-effort"
        fi
        [[ -e /etc/NIXOS ]] && args+=(-v /etc/NIXOS:/etc/NIXOS:ro)
    fi
    args+=("$image")

    docker "${args[@]}" >/dev/null || return 1
    printf "  ${GREEN}✓${RESET} pharos-beacon Docker container deployed for ${CYAN}%s${RESET}\n" "$host"
}

# ── heal fix mappings (INSPR-195 Phase 3) ──────────────────────────────────
#
# Each heal_fix_<slug> function corresponds to a check_<slug>. Output:
#   line 1: tier — "auto" | "confirm" | "manual"
#   line 2+: command (for auto/confirm) or explanation (for manual)
#
# Tier semantics:
#   auto    — safe, idempotent, can run with --yes. Examples: submodule init,
#             chmod on dir we own.
#   confirm — touches trust boundaries (known_hosts, gitconfig). Always asks.
#   manual  — can't be safely auto-applied (sudo, Keychain over SSH, secret-
#             touching). Print the command + explain WHY.
#
# Checks without a heal_fix mapping fall through to print the run_check
# fix hint. Coverage expands incrementally — start with highest-impact.

heal_fix_doctrine_nixcfg_kernel_present() {
    echo "auto"
    echo "cd '$NIXCFG_DIR' && git submodule update --init --recursive"
}
heal_fix_doctrine_inspr_kernel_present() {
    echo "auto"
    echo "cd '$INSPR_DIR' && git submodule update --init --recursive"
}
heal_fix_doctrine_fleetcom_kernel_present() {
    echo "auto"
    echo "cd '$FLEETCOM_DIR' && git submodule update --init --recursive"
}

heal_fix_no_legacy_gitconfig() {
    echo "confirm"
    echo "mv ~/.gitconfig ~/.gitconfig.legacy-$(date +%Y%m%d)"
}

heal_fix_agent_secrets_locked() {
    echo "confirm"
    echo "chmod 0500 '$SECRETS_DIR'"
}

heal_fix_paimos_auth() {
    echo "manual"
    cat <<MANUAL
Keyring authentication is missing or corrupted (typical: exit 36 on macOS).
Log in interactively AT THE KEYBOARD of the host — over-SSH access to
macOS Keychain is unreliable from non-GUI sessions (the well-known
imacw / INSPR-182 pattern).

At the host's keyboard, run:

  paimos auth login --url https://pm.barta.cm --name ppm

Then verify:  paimos auth whoami
Re-run:       inspr check
MANUAL
}

heal_fix_ssh_host_key() {
    echo "manual"
    cat <<MANUAL
Requires sudo — cannot be auto-applied by inspr (security-sensitive op).

Run at the host:
  sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' -C "root@$HOSTNAME_SHORT"

Then re-run: inspr check
MANUAL
}

# ── shared check-runner (so cmd_check + cmd_heal can both use it) ──────────
_run_all_check_sections() {
    section "Toolchain"
    run_check any nix_on_path "nix on PATH" \
        "Install Nix (multi-user installer); see playbook step 1"
    run_check workstation home_manager_on_path "home-manager on PATH" \
        "Install Home Manager standalone (nix run home-manager/master -- init); playbook step 6"
    run_check workstation paimos_on_path "paimos-cli on PATH" \
        "Add paimos-cli to home.packages in this host's home.nix; home-manager switch"
    run_check workstation devenv_on_path "devenv on PATH" \
        "Install via home-manager (inputs.devenv.packages.\${system}.devenv) — required by nixcfg .envrc"
    run_check workstation direnv_on_path "direnv on PATH" \
        "programs.direnv.enable = true in home.nix — precondition for agent-secrets auto-loading"

    section "Network / tailnet"
    run_check any tailscale_present "tailscale binary present" \
        "Install via 'brew install --cask tailscale-app' (macOS standalone) or distro pkg (Linux)"
    run_check any tailscale_up "tailscaled up + logged in" \
        "Open Tailscale.app or 'sudo tailscale up --login-server=https://hs.barta.cm'"
    run_check any headscale_reachable "https://hs.barta.cm/health reachable" \
        "Verify tailnet up; check DNS for hs.barta.cm; the URL is the SERVICE not the host"
    run_check any tailscale_control_url "tailnet name is hs.barta.cm (NOT Tailscale SaaS)" \
        "Tailscale is on wrong control server; reset via prefs OR 'tailscale up --login-server=https://hs.barta.cm --reset'"

    section "SSH"
    run_check any ssh_host_key "/etc/ssh/ssh_host_ed25519_key exists" \
        "macOS doesn't auto-generate; sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' -C \"root@${HOSTNAME_SHORT}\""
    run_check workstation user_ssh_key "~/.ssh/id_ed25519 OR id_rsa exists (user key for agenix decryption)" \
        "Generate one: ssh-keygen -t ed25519 (or scp existing from another host)"

    section "Secrets pipeline"
    run_check workstation agent_secrets_dir "$SECRETS_DIR exists" \
        "Enable inspr.secrets.agents in this host's home.nix; home-manager switch"
    run_check workstation agent_secrets_locked "$SECRETS_DIR mode 0500 (lock-after-activation)" \
        "chmod 0500 $SECRETS_DIR (or re-run home-manager switch)"
    run_check workstation agent_secrets_populated "$SECRETS_DIR contains decrypted .env files" \
        "Empty dir; verify secrets/agents/* are git-tracked and you're an AGE recipient"
    run_check server system_agenix_decrypted "/run/agenix/ exists + populated (NixOS age.secrets)" \
        "No secrets materialized; check NixOS agenix module + age.secrets.* declarations + reboot/switch"
    run_check any host_in_agenix_recipients "host '$HOSTNAME_SHORT' is an agenix recipient in nixcfg/secrets/secrets.nix" \
        "Add this host's /etc/ssh/ssh_host_ed25519_key.pub to secrets.nix HOST KEYS section; just rekey"

    section "Identity / auth"
    run_check any no_legacy_gitconfig "no legacy ~/.gitconfig (would silently override HM XDG config)" \
        "mv ~/.gitconfig ~/.gitconfig.legacy-\$(date +%Y%m%d) — HM XDG config will then take effect"
    run_check any git_identity_personal_default "git default identity = Markus Barta <markus@barta.com>" \
        "Add modules/shared/git-identity.nix to imports + inspr.git-identity.enable = true"
    run_check workstation gh_auth "gh CLI authenticated (gh api user succeeds)" \
        "gh auth login (or check that GH_TOKEN.env materialized correctly)"
    run_check workstation paimos_instance_config "~/.paimos/config.yaml present, mode 0600, and free of legacy api_key" \
        "First migrate without ambient overrides: env -u PAIMOS_URL -u PAIMOS_API_KEY -u PPM_URL -u PPMAPIKEY paimos auth whoami; retry home-manager switch; only if authentication still fails, run interactively: paimos auth login --url https://pm.barta.cm --name ppm"
    run_check workstation paimos_auth "paimos auth whoami succeeds using instance config + keyring" \
        "First ensure paimos_instance_config passes. Then log in interactively: paimos auth login --url https://pm.barta.cm --name ppm. On macOS, run at the keyboard (not over SSH — Keychain is unreliable from non-GUI sessions). See /ppm domain pack."

    section "Drift"
    run_check workstation nixcfg_envrc_canonical_path "nixcfg .envrc references INSPR-164 canonical path (~/.inspr/secrets/agents)" \
        "cd $NIXCFG_DIR && git pull — your checkout predates the 2026-05-13 INSPR-164 path migration"
    run_check workstation nixcfg_envrc_content_filter "nixcfg .envrc has content-aware filter (Ghostty-leak prevention)" \
        "cd $NIXCFG_DIR && git pull — content-filter landed 2026-05-13 after Ghostty scrollback incident; never remove the [A-Z_][A-Z0-9_]*= guard"
    run_check workstation secrets_audit_clean "secrets-audit reports zero drift" \
        "cd $NIXCFG_DIR && ./scripts/secrets-audit.sh — backfill missing or remove orphan declarations"

    section "Code repos"
    run_check workstation repo_nixcfg "$NIXCFG_DIR present" \
        "git clone https://github.com/markus-barta/nixcfg.git $NIXCFG_DIR"
    run_check workstation repo_inspr "$INSPR_DIR present" \
        "git clone https://github.com/inspr-at/inspr.git $INSPR_DIR (private)"
    run_check workstation repo_fleetcom "$FLEETCOM_DIR present" \
        "git clone https://github.com/markus-barta/fleetcom.git $FLEETCOM_DIR"

    section "Doctrine (Phase 6, INSPR-187)"
    run_check workstation doctrine_nixcfg_kernel_present "nixcfg/doctrine submodule initialized + KERNEL.md present" \
        "cd $NIXCFG_DIR && git submodule update --init --recursive  # NOT just git pull --recurse-submodules"
    run_check workstation doctrine_inspr_kernel_present "inspr/doctrine submodule initialized + KERNEL.md present" \
        "cd $INSPR_DIR && git submodule update --init --recursive"
    run_check workstation doctrine_fleetcom_kernel_present "fleetcom/doctrine submodule initialized + KERNEL.md present" \
        "cd $FLEETCOM_DIR && git submodule update --init --recursive"
    run_check workstation doctrine_nixcfg_claude_md_loader "nixcfg/CLAUDE.md @-refs kernel (not legacy CORE+PROFILE)" \
        "edit $NIXCFG_DIR/CLAUDE.md to use @./doctrine/docs/AGENTS-KERNEL.md (drop CORE+PROFILE @-refs)"
    run_check workstation doctrine_inspr_claude_md_loader "inspr/CLAUDE.md @-refs kernel (not legacy CORE+PROFILE)" \
        "edit $INSPR_DIR/CLAUDE.md to use @./doctrine/docs/AGENTS-KERNEL.md"
    run_check workstation doctrine_fleetcom_claude_md_loader "fleetcom/CLAUDE.md @-refs kernel (not legacy CORE+PROFILE)" \
        "edit $FLEETCOM_DIR/CLAUDE.md to use @./doctrine/docs/AGENTS-KERNEL.md"
    run_check workstation doctrine_kernel_size_budget "kernel is ≤12000 bytes (gatekeeper budget)" \
        "trim $NIXCFG_DIR/doctrine/docs/AGENTS-KERNEL.md OR move content to a domain pack"
}

# ── sub-commands ────────────────────────────────────────────────────────────

cmd_version() {
    echo "inspr $INSPR_VERSION"
}

cmd_help() {
    echo "${CYAN}${BOLD}${INSPR_ART_HELP}${RESET}"
    echo ""
    echo "  ${BOLD}inspr${RESET} — agent-ready operating layer for builders."
    echo "  Solve, automate, invent, fix, ship — with AI agents as first-class collaborators."
    echo "  Run ${CYAN}inspr --vision${RESET} for the full mission statement."
    echo ""
    echo "${BOLD}Usage:${RESET}"
    echo "  inspr <command> [flags]"
    echo "  inspr <flag>"
    echo ""
    echo "${BOLD}Commands:${RESET}"
    echo "  ${GREEN}check${RESET}      Read-only diagnosis — am I onboarded? what drifted?"
    echo "  ${GREEN}heal${RESET}       Diagnose, then offer to fix what's fixable."
    echo "  ${GREEN}onboard${RESET}    Walk a fresh host through INSPR setup."
    echo "  ${GREEN}post-deploy${RESET} Validate nixcfg → Pharos → HostDash after deploy."
    echo ""
    echo "${BOLD}Flags:${RESET}"
    echo "  ${CYAN}--help, -h${RESET}       Show this help."
    echo "  ${CYAN}--vision${RESET}         Show the full vision statement."
    echo "  ${CYAN}--version${RESET}        Show inspr version."
    echo ""
    echo "${BOLD}Sub-command flags${RESET} (see each sub-command's help for full list):"
    echo "  ${DIM}inspr check --verbose | --quiet | --list | --profile=<workstation|server>${RESET}"
    echo "  ${DIM}inspr heal --yes${RESET}     ${DIM}# auto-apply fixable items (NOT YET IMPLEMENTED — see INSPR-195)${RESET}"
    echo "  ${DIM}inspr onboard${RESET}         ${DIM}# interactive walkthrough (NOT YET IMPLEMENTED — see INSPR-195)${RESET}"
    echo "  ${DIM}inspr post-deploy --host=hsb8${RESET}"
    echo ""
}

cmd_vision() {
    echo "${CYAN}${BOLD}${INSPR_ART_VISION}${RESET}"
    echo ""
    local vision_md="$INSPR_DIR/VISION.md"
    if [[ -f "$vision_md" ]]; then
        render_markdown "$vision_md"
    else
        echo "${YELLOW}warning:${RESET} $vision_md not found." >&2
        echo "${DIM}(VISION.md should live at \$INSPR_DIR/VISION.md — set INSPR_DIR or clone inspr repo)${RESET}" >&2
        return 1
    fi
}

cmd_check_help() {
    cat <<EOF
${BOLD}inspr check${RESET} — read-only diagnosis of INSPR-onboarding state.

${BOLD}Usage:${RESET}
  inspr check [flags]

${BOLD}Flags:${RESET}
  ${CYAN}-v, --verbose${RESET}              Include diagnostic output for failed checks.
  ${CYAN}-q, --quiet${RESET}                Only print failures + summary.
  ${CYAN}--list${RESET}                     List all checks without running.
  ${CYAN}--profile=<p>${RESET}              Override auto-detected profile (workstation|server).
  ${CYAN}-h, --help${RESET}                 Show this help.

${BOLD}Exit codes:${RESET}
  0  all checks passed (or only skips)
  1  one or more checks failed
  2  usage / environment error

${BOLD}Profile detection:${RESET}
  Workstation = home-manager on PATH (user dev hosts).
  Server      = otherwise (NixOS infra hosts).
  Override via ${CYAN}--profile=<p>${RESET} or ${CYAN}\$INSPR_DOCTOR_PROFILE${RESET}.

${DIM}Each check is a function check_<slug> returning 0=pass, 1=fail, 77=skip.
Hints on failure point at the playbook step or the fix command.${RESET}
EOF
}

cmd_check() {
    # Parse sub-command flags
    VERBOSE=0
    QUIET=0
    LIST_ONLY=0
    local profile_override=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -v | --verbose) VERBOSE=1 ;;
        -q | --quiet) QUIET=1 ;;
        --list) LIST_ONLY=1 ;;
        --profile=*) profile_override="${1#--profile=}" ;;
        --profile)
            shift
            profile_override="$1"
            ;;
        -h | --help)
            cmd_check_help
            exit 0
            ;;
        *)
            echo "${RED}error:${RESET} unknown flag for 'inspr check': '$1' (try --help)" >&2
            exit 2
            ;;
        esac
        shift
    done

    PROFILE="$(detect_profile "$profile_override")"
    case "$PROFILE" in
    workstation | server) ;;
    *)
        echo "${RED}error:${RESET} unknown profile '$PROFILE' (must be workstation or server)" >&2
        exit 2
        ;;
    esac

    PASS=0
    FAIL=0
    SKIP=0
    FAILED_CHECKS=()

    if [[ $LIST_ONLY -eq 0 && $QUIET -eq 0 ]]; then
        echo "${BOLD}inspr check${RESET} — host: ${CYAN}$HOSTNAME_SHORT${RESET} ${DIM}(profile: ${PROFILE})${RESET}"
    fi

    _run_all_check_sections

    [[ $LIST_ONLY -eq 1 ]] && exit 0

    TOTAL=$((PASS + FAIL + SKIP))
    echo ""
    if [[ $FAIL -eq 0 ]]; then
        echo "${GREEN}${BOLD}✓ inspr check: all checks passed${RESET} (${PASS}/${TOTAL}, ${SKIP} skipped) ${DIM}— profile: ${PROFILE}${RESET}"
        exit 0
    else
        echo "${RED}${BOLD}✗ inspr check: ${FAIL} check(s) failed${RESET} (${PASS}/${TOTAL}, ${SKIP} skipped) ${DIM}— profile: ${PROFILE}${RESET}"
        [[ $VERBOSE -eq 0 ]] && echo "  ${DIM}re-run with --verbose for diagnostic output${RESET}"
        echo "  ${DIM}for fix suggestions on red items, run:${RESET} ${CYAN}inspr heal${RESET}"
        exit 1
    fi
}

cmd_heal_help() {
    cat <<EOF
${BOLD}inspr heal${RESET} — diagnose, then offer to fix what's fixable.

${BOLD}Usage:${RESET}
  inspr heal [flags]

${BOLD}Flags:${RESET}
  ${CYAN}-y, --yes${RESET}        Auto-apply 🟢 auto-tier fixes without prompting.
                   (Confirm + manual tiers still prompt / print.)
  ${CYAN}--profile=<p>${RESET}    Override auto-detected profile (workstation|server).
  ${CYAN}-h, --help${RESET}       Show this help.

${BOLD}Fix tiers:${RESET}
  ${GREEN}🟢 auto${RESET}      Safe, idempotent (submodule init, chmod on owned dirs).
              With --yes: applied automatically. Without: prompts y/N.
  ${YELLOW}🟡 confirm${RESET}   Touches trust boundaries (legacy gitconfig backup, etc.).
              Always prompts y/N regardless of --yes.
  ${RED}🔴 manual${RESET}    Can't be auto-applied (sudo, Keychain-over-SSH, etc.).
              Prints the command + explains WHY it can't be automated.

${BOLD}Symptom→fix coverage:${RESET}
  Heal mappings are added incrementally. Symptoms without a known fix
  fall through to the run_check 'fix:' hint. Run ${CYAN}inspr check --verbose${RESET}
  to see all hints; file an INSPR ticket if a recurring symptom needs
  a heal mapping.
EOF
}

cmd_heal() {
    local auto_yes=0
    local profile_override=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
        -y | --yes) auto_yes=1 ;;
        --profile=*) profile_override="${1#--profile=}" ;;
        --profile)
            shift
            profile_override="$1"
            ;;
        -h | --help)
            cmd_heal_help
            exit 0
            ;;
        *)
            echo "${RED}error:${RESET} unknown flag for 'inspr heal': '$1' (try --help)" >&2
            exit 2
            ;;
        esac
        shift
    done

    PROFILE="$(detect_profile "$profile_override")"
    case "$PROFILE" in
    workstation | server) ;;
    *)
        echo "${RED}error:${RESET} unknown profile '$PROFILE'" >&2
        exit 2
        ;;
    esac

    VERBOSE=0
    QUIET=0
    LIST_ONLY=0
    PASS=0
    FAIL=0
    SKIP=0
    FAILED_CHECKS=()

    echo "${BOLD}inspr heal${RESET} — host: ${CYAN}$HOSTNAME_SHORT${RESET} ${DIM}(profile: ${PROFILE})${RESET}"

    # Run the same check pipeline; failures populate FAILED_CHECKS.
    _run_all_check_sections

    TOTAL=$((PASS + FAIL + SKIP))
    echo ""

    if [[ $FAIL -eq 0 ]]; then
        echo "${GREEN}${BOLD}✓ inspr heal: nothing to heal — all ${PASS}/${TOTAL} checks passed.${RESET}"
        exit 0
    fi

    echo "${YELLOW}${BOLD}Found ${FAIL} issue(s).${RESET} Reviewing each:"
    echo ""

    local healed=0 deferred=0 unfixable=0 no_mapping=0

    for slug in "${FAILED_CHECKS[@]}"; do
        local fix_fn="heal_fix_${slug}"
        if ! declare -f "$fix_fn" >/dev/null; then
            printf "  ${YELLOW}?${RESET} ${BOLD}%s${RESET}\n" "$slug"
            printf "     ${DIM}no auto-heal mapping yet — see 'inspr check --verbose' for the fix hint${RESET}\n\n"
            no_mapping=$((no_mapping + 1))
            continue
        fi

        local fix_info tier action
        fix_info=$("$fix_fn")
        tier=$(echo "$fix_info" | head -1)
        action=$(echo "$fix_info" | tail -n +2)

        case "$tier" in
        auto)
            printf "  ${GREEN}🟢 AUTO${RESET}     ${BOLD}%s${RESET}\n" "$slug"
            printf "     ${DIM}\$${RESET} %s\n" "$action"
            if [[ $auto_yes -eq 1 ]]; then
                if bash -c "$action" 2>&1 | sed 's/^/     /'; then
                    printf "     ${GREEN}✓ applied${RESET}\n\n"
                    healed=$((healed + 1))
                else
                    printf "     ${RED}✗ failed${RESET}\n\n"
                fi
            else
                printf "     Apply? [y/N] "
                read -r ans
                if [[ "$ans" =~ ^[Yy] ]]; then
                    if bash -c "$action" 2>&1 | sed 's/^/     /'; then
                        printf "     ${GREEN}✓ applied${RESET}\n\n"
                        healed=$((healed + 1))
                    else
                        printf "     ${RED}✗ failed${RESET}\n\n"
                    fi
                else
                    printf "     ${DIM}deferred${RESET}\n\n"
                    deferred=$((deferred + 1))
                fi
            fi
            ;;
        confirm)
            printf "  ${YELLOW}🟡 CONFIRM${RESET}  ${BOLD}%s${RESET}\n" "$slug"
            printf "     ${DIM}\$${RESET} %s\n" "$action"
            printf "     Apply? [y/N] "
            read -r ans
            if [[ "$ans" =~ ^[Yy] ]]; then
                if bash -c "$action" 2>&1 | sed 's/^/     /'; then
                    printf "     ${GREEN}✓ applied${RESET}\n\n"
                    healed=$((healed + 1))
                else
                    printf "     ${RED}✗ failed${RESET}\n\n"
                fi
            else
                printf "     ${DIM}deferred${RESET}\n\n"
                deferred=$((deferred + 1))
            fi
            ;;
        manual)
            printf "  ${RED}🔴 MANUAL${RESET}   ${BOLD}%s${RESET}\n" "$slug"
            echo "$action" | sed 's/^/     /'
            printf "\n"
            unfixable=$((unfixable + 1))
            ;;
        *)
            printf "  ${RED}?${RESET}  ${BOLD}%s${RESET}: unknown tier '%s' in heal_fix function (script bug)\n\n" "$slug" "$tier"
            ;;
        esac
    done

    echo "${BOLD}heal summary:${RESET} ${GREEN}${healed} applied${RESET}, ${YELLOW}${deferred} deferred${RESET}, ${RED}${unfixable} need manual action${RESET}, ${DIM}${no_mapping} no mapping yet${RESET}"
    echo ""
    echo "${DIM}re-run 'inspr check' to verify state${RESET}"
    if [[ $((unfixable + no_mapping)) -eq 0 && $deferred -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

cmd_onboard_help() {
    cat <<EOF
${BOLD}inspr onboard${RESET} — walk a fresh host through INSPR setup.

${BOLD}Usage:${RESET}
  inspr onboard [flags]

${BOLD}Flags:${RESET}
  ${CYAN}--profile=<p>${RESET}              Override auto-detected profile (workstation|server).
  ${CYAN}--pharos-register${RESET}          Register this host through Pharos /register.
  ${CYAN}--pharos-url=<url>${RESET}         Pharos base URL. Default: \$INSPR_PHAROS_URL or http://100.64.0.4:8088.
  ${CYAN}--host=<h>${RESET}                 Host slug. Default: short hostname.
  ${CYAN}--role=<r>${RESET}                 Pharos role. Default: server or workstation.
  ${CYAN}--nix / --non-nix${RESET}          Override Nix host detection.
  ${CYAN}--heartbeat-interval=<sec>${RESET} Beacon cadence. Default: 60.
  ${CYAN}--pharos-token-out=<path>${RESET}  Where to write PHAROS_TOKEN. Default: ~/.config/pharos/pharos-beacon.env.
  ${CYAN}--pharos-deploy=docker|none${RESET} Deploy pharos-beacon after registration or from an existing token file.
  ${CYAN}--pharos-image=<image>${RESET}      Beacon image for Docker deploy. Default: ghcr.io/inspr-at/pharos/pharosd:latest.
  ${CYAN}-h, --help${RESET}                 Show this help.

${BOLD}What it does:${RESET}
  Prints the 10-step new-host onboarding sequence, runs ${CYAN}inspr check${RESET},
  and overlays the per-step status (✅ done / ⚠ partial / ❌ missing).
  For each step with gaps, shows the next action(s) needed.

  With ${CYAN}--pharos-register${RESET}, posts a HostRegistration to Pharos using
  ${CYAN}INSPR_PHAROS_REGISTRATION_TOKEN${RESET}. The returned per-host beacon
  token is written to a 0600 env file and is never printed.

${BOLD}Resume-friendly:${RESET}
  Re-running picks up at the first incomplete step. Already-done steps
  pass silently.
EOF
}

cmd_onboard() {
    local profile_override=""
    local pharos_register=0
    local pharos_url="${INSPR_PHAROS_URL:-http://100.64.0.4:8088}"
    local pharos_host="$HOSTNAME_SHORT"
    local pharos_role=""
    local pharos_is_nix=""
    local pharos_interval="${INSPR_PHAROS_INTERVAL:-60}"
    local pharos_token_out="${INSPR_PHAROS_TOKEN_OUT:-$HOME/.config/pharos/pharos-beacon.env}"
    local pharos_deploy="${INSPR_PHAROS_DEPLOY:-none}"
    local pharos_image="${INSPR_PHAROS_IMAGE:-ghcr.io/inspr-at/pharos/pharosd:latest}"

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --profile=*) profile_override="${1#--profile=}" ;;
        --profile)
            shift
            profile_override="$1"
            ;;
        --pharos-register) pharos_register=1 ;;
        --pharos-url=*) pharos_url="${1#--pharos-url=}" ;;
        --pharos-url)
            shift
            pharos_url="$1"
            ;;
        --host=*) pharos_host="${1#--host=}" ;;
        --host)
            shift
            pharos_host="$1"
            ;;
        --role=*) pharos_role="${1#--role=}" ;;
        --role)
            shift
            pharos_role="$1"
            ;;
        --nix) pharos_is_nix="true" ;;
        --non-nix) pharos_is_nix="false" ;;
        --heartbeat-interval=*) pharos_interval="${1#--heartbeat-interval=}" ;;
        --heartbeat-interval)
            shift
            pharos_interval="$1"
            ;;
        --pharos-token-out=*) pharos_token_out="${1#--pharos-token-out=}" ;;
        --pharos-token-out)
            shift
            pharos_token_out="$1"
            ;;
        --pharos-deploy=*) pharos_deploy="${1#--pharos-deploy=}" ;;
        --pharos-deploy)
            shift
            pharos_deploy="$1"
            ;;
        --pharos-image=*) pharos_image="${1#--pharos-image=}" ;;
        --pharos-image)
            shift
            pharos_image="$1"
            ;;
        -h | --help)
            cmd_onboard_help
            exit 0
            ;;
        *)
            echo "${RED}error:${RESET} unknown flag for 'inspr onboard': '$1' (try --help)" >&2
            exit 2
            ;;
        esac
        shift
    done

    PROFILE="$(detect_profile "$profile_override")"
    case "$PROFILE" in
    workstation | server) ;;
    *)
        echo "${RED}error:${RESET} unknown profile '$PROFILE'" >&2
        exit 2
        ;;
    esac
    pharos_role="${pharos_role:-$(pharos_default_role)}"
    pharos_is_nix="${pharos_is_nix:-$(pharos_default_is_nix)}"
    pharos_url="${pharos_url%/}"
    case "$pharos_deploy" in
    none | docker) ;;
    *)
        echo "${RED}error:${RESET} --pharos-deploy must be docker or none" >&2
        exit 2
        ;;
    esac
    pharos_validate_host "$pharos_host" || {
        echo "${RED}error:${RESET} unsafe host slug '$pharos_host'" >&2
        exit 2
    }
    pharos_validate_interval "$pharos_interval" || {
        echo "${RED}error:${RESET} --heartbeat-interval must be a positive integer" >&2
        exit 2
    }
    case "$pharos_is_nix" in
    true | false) ;;
    *)
        echo "${RED}error:${RESET} internal Nix detection produced invalid value '$pharos_is_nix'" >&2
        exit 2
        ;;
    esac

    VERBOSE=0
    QUIET=1 # silent during check pipeline; we'll overlay step-status
    LIST_ONLY=0
    PASS=0
    FAIL=0
    SKIP=0
    FAILED_CHECKS=()

    echo "${BOLD}inspr onboard${RESET} — host: ${CYAN}$HOSTNAME_SHORT${RESET} ${DIM}(profile: ${PROFILE})${RESET}"
    echo ""
    echo "${DIM}Running diagnostics silently to determine per-step status...${RESET}"
    _run_all_check_sections >/dev/null 2>&1

    echo ""
    echo "${BOLD}${CYAN}10-step INSPR onboarding sequence${RESET}"
    echo ""

    # Step → check slug mapping. A step is ✅ if all its checks pass,
    # ⚠ partial if some, ❌ missing if all fail or skip.
    # Helper: returns "ok" | "partial" | "missing" based on FAILED_CHECKS
    _step_status() {
        local fails=0 total=0
        for slug in "$@"; do
            total=$((total + 1))
            if [[ ${#FAILED_CHECKS[@]} -gt 0 ]]; then
                for failed in "${FAILED_CHECKS[@]}"; do
                    if [[ "$failed" == "$slug" ]]; then
                        fails=$((fails + 1))
                        break
                    fi
                done
            fi
        done
        if [[ $fails -eq 0 ]]; then
            echo "ok"
        elif [[ $fails -eq $total ]]; then
            echo "missing"
        else
            echo "partial"
        fi
    }

    _step_label() {
        local status="$1" num="$2" desc="$3"
        case "$status" in
        ok) printf "  ${GREEN}✅ Step %d${RESET}  %s\n" "$num" "$desc" ;;
        partial) printf "  ${YELLOW}⚠  Step %d${RESET}  %s ${DIM}(partial)${RESET}\n" "$num" "$desc" ;;
        missing) printf "  ${RED}❌ Step %d${RESET}  %s\n" "$num" "$desc" ;;
        esac
    }

    # 1. Repo clones
    local s1
    s1=$(_step_status repo_nixcfg repo_inspr repo_fleetcom)
    _step_label "$s1" 1 "Clone nixcfg + inspr + fleetcom under ~/Code/"
    if [[ "$s1" != "ok" ]]; then
        echo "     ${DIM}\$${RESET} git clone https://github.com/markus-barta/nixcfg.git ~/Code/nixcfg"
        echo "     ${DIM}\$${RESET} git clone https://github.com/inspr-at/inspr.git ~/Code/inspr"
        echo "     ${DIM}\$${RESET} git clone https://github.com/markus-barta/fleetcom.git ~/Code/fleetcom"
    fi

    # 2. Doctrine submodules initialized
    local s2
    s2=$(_step_status doctrine_nixcfg_kernel_present doctrine_inspr_kernel_present doctrine_fleetcom_kernel_present)
    _step_label "$s2" 2 "Initialize doctrine submodules (Phase-5.QA1 gotcha)"
    if [[ "$s2" != "ok" ]]; then
        echo "     ${DIM}\$${RESET} for r in ~/Code/{nixcfg,inspr,fleetcom}; do (cd \"\$r\" && git submodule update --init --recursive); done"
    fi

    # 3. Tailscale → Headscale
    local s3
    s3=$(_step_status tailscale_present tailscale_up headscale_reachable tailscale_control_url)
    _step_label "$s3" 3 "Tailscale joined to Headscale at hs.barta.cm"
    if [[ "$s3" != "ok" ]]; then
        echo "     ${DIM}\$${RESET} sudo tailscale up --login-server=https://hs.barta.cm"
    fi

    # 4. Agent env-files materialized
    local s4
    s4=$(_step_status agent_secrets_dir agent_secrets_locked agent_secrets_populated)
    _step_label "$s4" 4 "Agent env-files at ~/.inspr/secrets/agents/ (INSPR-164)"
    if [[ "$s4" != "ok" ]]; then
        echo "     Enable ${CYAN}inspr.secrets.agents${RESET} in this host's home.nix; run ${CYAN}home-manager switch${RESET}"
    fi

    # 5. macOS host-recipient key
    local s5
    s5=$(_step_status ssh_host_key)
    _step_label "$s5" 5 "macOS host-recipient ed25519 key (for agenix decryption)"
    if [[ "$s5" != "ok" ]]; then
        echo "     ${DIM}\$${RESET} sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N '' -C \"root@${HOSTNAME_SHORT}\""
        echo "     ${DIM}(NixOS auto-generates this; macOS does not)${RESET}"
    fi

    # 6. SSH trust preset (host added to nixcfg ssh-keyring)
    local s6
    s6=$(_step_status host_in_agenix_recipients user_ssh_key)
    _step_label "$s6" 6 "SSH trust preset (host admitted to fleet ssh-keyring)"
    if [[ "$s6" != "ok" ]]; then
        echo "     Add this host to ${CYAN}modules/shared/ssh-keyring.nix${RESET} (inspr.ssh.authorized preset)"
        echo "     and add the host's public key to ${CYAN}secrets/secrets.nix${RESET} HOST KEYS section"
    fi

    # 7. paimos instance config + interactive login
    local s7
    s7=$(_step_status paimos_on_path paimos_instance_config paimos_auth)
    _step_label "$s7" 7 "paimos CLI instance config + interactive login"
    if [[ "$s7" != "ok" ]]; then
        echo "     First migrate any legacy config without ambient overrides:"
        echo "     ${DIM}\$${RESET} env -u PAIMOS_URL -u PAIMOS_API_KEY -u PPM_URL -u PPMAPIKEY paimos auth whoami"
        echo "     Retry home-manager switch. Only after the legacy-config guard clears,"
        echo "     authenticate ${YELLOW}AT THE HOST'S KEYBOARD${RESET} (not over SSH):"
        echo "     ${DIM}\$${RESET} paimos auth login --url https://pm.barta.cm --name ppm"
    fi

    # 8. Nix toolchain + devenv
    local s8
    s8=$(_step_status nix_on_path home_manager_on_path devenv_on_path direnv_on_path)
    _step_label "$s8" 8 "Nix toolchain + devenv + direnv on PATH"
    if [[ "$s8" != "ok" ]]; then
        echo "     Install Nix (multi-user); run ${CYAN}home-manager switch${RESET} per nixcfg/hosts/<this-host>/home.nix"
    fi

    # 9. Smoke (this very tool)
    local s9
    if [[ $FAIL -eq 0 ]]; then
        s9="ok"
    elif [[ $FAIL -lt 5 ]]; then
        s9="partial"
    else
        s9="missing"
    fi
    _step_label "$s9" 9 "Smoke: 'inspr check' returns ${GREEN}all green${RESET}"
    if [[ "$s9" != "ok" ]]; then
        echo "     ${DIM}\$${RESET} inspr check               ${DIM}# see what's broken${RESET}"
        echo "     ${DIM}\$${RESET} inspr heal                ${DIM}# offer to fix what's fixable${RESET}"
    fi

    # 10. Pharos host registry + pharos-beacon
    local s10
    s10="$(pharos_step_status "$pharos_token_out")"
    _step_label "$s10" 10 "Pharos registration + pharos-beacon deployment (PHAROS-7)"
    if [[ "$s10" != "ok" ]]; then
        echo "     ${DIM}\$${RESET} INSPR_PHAROS_REGISTRATION_TOKEN=... inspr onboard --pharos-register --pharos-deploy=docker"
        echo "     ${DIM}token target:${RESET} $pharos_token_out"
    fi

    if [[ $pharos_register -eq 1 || "$pharos_deploy" != "none" ]]; then
        section "Pharos onboarding"
        if [[ $pharos_register -eq 1 ]]; then
            pharos_register_host "$pharos_url" "$pharos_host" "$pharos_role" "$pharos_is_nix" "$pharos_interval" "$pharos_token_out" || exit $?
        fi
        if [[ "$pharos_deploy" == "docker" ]]; then
            pharos_deploy_beacon_docker "$pharos_url" "$pharos_host" "$pharos_role" "$pharos_is_nix" "$pharos_interval" "$pharos_token_out" "$pharos_image" || exit $?
        fi
    fi

    echo ""

    if [[ $FAIL -eq 0 && "$(pharos_step_status "$pharos_token_out")" == "ok" ]]; then
        echo "${GREEN}${BOLD}✓ inspr onboard: this host is fully onboarded.${RESET}"
        exit 0
    fi

    echo "${BOLD}Next:${RESET} address steps above with ${RED}❌${RESET} (missing) or ${YELLOW}⚠${RESET} (partial), then re-run ${CYAN}inspr onboard${RESET} to verify."
    echo "${DIM}For interactive fix-application, try${RESET} ${CYAN}inspr heal${RESET} ${DIM}(works on auto-fixable items).${RESET}"
    exit 1
}

cmd_post_deploy_help() {
    cat <<EOF
${BOLD}inspr post-deploy${RESET} — validate nixcfg → Pharos → HostDash after deploy.

${BOLD}Usage:${RESET}
  inspr post-deploy --host=<host> [flags]

${BOLD}Flags:${RESET}
  ${CYAN}--host=<h>${RESET}             Host slug to validate, e.g. hsb8. Required.
  ${CYAN}--context=<c>${RESET}          HostDash URL context: lan | tailnet | both. Default: tailnet.
  ${CYAN}--pharos-url=<url>${RESET}     Pharos base URL. Default: \$INSPR_PHAROS_URL or http://100.64.0.4:8088.
  ${CYAN}--nixcfg-dir=<dir>${RESET}     nixcfg checkout. Default: \$INSPR_NIXCFG_DIR or ~/Code/nixcfg.
  ${CYAN}--ssh-host=<h>${RESET}         SSH target for live /etc manifest check. Default: --host value.
  ${CYAN}--skip-ssh${RESET}             Skip live /etc/hostdash-config/<host>.json check.
  ${CYAN}-h, --help${RESET}             Show this help.

${BOLD}What it checks:${RESET}
  - nixcfg can evaluate the generated declared manifest.
  - csb1 pharosd handoff artifact matches the generated manifest when present.
  - live host /etc manifest matches the generated manifest unless --skip-ssh.
  - Pharos /declared-hosts.json contains the host with separate observed runtime state.
  - HostDash responds in requested LAN/Tailscale contexts and serves the same manifest.

${BOLD}Exit codes:${RESET}
  0  validation passed or only optional checks skipped
  1  one or more validation checks failed
  2  usage / environment error
EOF
}

cmd_post_deploy() {
    local host=""
    local context="tailnet"
    local pharos_url="${INSPR_PHAROS_URL:-http://100.64.0.4:8088}"
    local nixcfg_dir="$NIXCFG_DIR"
    local ssh_host=""
    local skip_ssh=0

    while [[ $# -gt 0 ]]; do
        case "$1" in
        --host=*) host="${1#--host=}" ;;
        --host)
            shift
            host="$1"
            ;;
        --context=*) context="${1#--context=}" ;;
        --context)
            shift
            context="$1"
            ;;
        --pharos-url=*) pharos_url="${1#--pharos-url=}" ;;
        --pharos-url)
            shift
            pharos_url="$1"
            ;;
        --nixcfg-dir=*) nixcfg_dir="${1#--nixcfg-dir=}" ;;
        --nixcfg-dir)
            shift
            nixcfg_dir="$1"
            ;;
        --ssh-host=*) ssh_host="${1#--ssh-host=}" ;;
        --ssh-host)
            shift
            ssh_host="$1"
            ;;
        --skip-ssh) skip_ssh=1 ;;
        -h | --help)
            cmd_post_deploy_help
            exit 0
            ;;
        *)
            echo "${RED}error:${RESET} unknown flag for 'inspr post-deploy': '$1' (try --help)" >&2
            exit 2
            ;;
        esac
        shift
    done

    if [[ -z "$host" ]]; then
        echo "${RED}error:${RESET} --host is required" >&2
        exit 2
    fi
    if [[ ! "$host" =~ ^[A-Za-z0-9._-]+$ ]]; then
        echo "${RED}error:${RESET} unsafe host slug '$host'" >&2
        exit 2
    fi
    case "$context" in
    lan | tailnet | both) ;;
    *)
        echo "${RED}error:${RESET} --context must be lan, tailnet, or both" >&2
        exit 2
        ;;
    esac

    ssh_host="${ssh_host:-$host}"
    pharos_url="${pharos_url%/}"

    local tmpdir generated_json pharos_json live_manifest served_manifest artifact
    tmpdir="$(mktemp -d)" || exit 2
    trap 'rm -rf "$tmpdir"' EXIT
    generated_json="$tmpdir/generated.json"
    pharos_json="$tmpdir/pharos.json"
    live_manifest="$tmpdir/live-hostdash.json"
    served_manifest="$tmpdir/served-hostdash.json"
    artifact="$nixcfg_dir/hosts/csb1/docker/pharos/manifests/${host}.json"

    POST_PASS=0
    POST_FAIL=0
    POST_SKIP=0

    echo "${BOLD}inspr post-deploy${RESET} — host: ${CYAN}$host${RESET} ${DIM}(context: ${context})${RESET}"

    section "nixcfg declaration"
    if [[ ! -d "$nixcfg_dir/.git" ]]; then
        post_fail "nixcfg checkout is present" "INSPR/NIX: set --nixcfg-dir or INSPR_NIXCFG_DIR"
    elif (cd "$nixcfg_dir" && nix eval ".#nixosConfigurations.${host}.config.services.hostdash.manifest.generated" --json >"$generated_json" 2>"$tmpdir/nix-eval.err"); then
        post_pass "nixcfg generated manifest evaluates"
        post_check_json "generated manifest schema/version/host" "NIX-277/NIX-279" "$generated_json" \
            --arg host "$host" '.schema == "inspr.hostdash.config.v1" and .version == 1 and .host.name == $host and .policy.declaredOnly == true'
    else
        post_fail "nixcfg generated manifest evaluates" "NIX-277/NIX-279"
    fi

    if [[ -s "$generated_json" && -f "$artifact" ]]; then
        if diff -u <(jq -S . "$generated_json") <(jq -S . "$artifact") >/dev/null; then
            post_pass "csb1 pharosd handoff artifact matches generated manifest"
        else
            post_fail "csb1 pharosd handoff artifact matches generated manifest" "NIX-286"
        fi
    elif [[ -s "$generated_json" ]]; then
        post_skip "csb1 pharosd handoff artifact" "no artifact at $artifact"
    fi

    if [[ -s "$generated_json" && $skip_ssh -eq 0 ]]; then
        if command -v ssh >/dev/null 2>&1 && ssh "$ssh_host" "test -s /etc/hostdash-config/${host}.json && cat /etc/hostdash-config/${host}.json" >"$live_manifest" 2>/dev/null; then
            if diff -u <(jq -S . "$generated_json") <(jq -S . "$live_manifest") >/dev/null; then
                post_pass "live host /etc manifest matches generated manifest"
            else
                post_fail "live host /etc manifest matches generated manifest" "NIX deploy"
            fi
        else
            post_fail "live host /etc manifest is reachable over SSH" "NIX deploy/runbook"
        fi
    elif [[ $skip_ssh -eq 1 ]]; then
        post_skip "live host /etc manifest" "--skip-ssh set"
    fi

    section "Pharos"
    if curl -fsS -m 8 "$pharos_url/declared-hosts.json" >"$pharos_json" 2>/dev/null; then
        post_pass "Pharos declared-hosts endpoint responds"
        post_check_json "Pharos response schema" "PHAROS-29" "$pharos_json" \
            '.schema == "inspr.pharos.declared-hosts.v1" and .manifest_schema == "inspr.hostdash.config.v1"'
        post_check_json "Pharos has declared host" "PHAROS-29/NIX-286" "$pharos_json" \
            --arg host "$host" 'any(.declared_hosts[]; .name == $host and .declared.host.name == $host)'
        post_check_json "Pharos runtime overlay is observed" "PHAROS-29/pharos-beacon" "$pharos_json" \
            --arg host "$host" 'any(.declared_hosts[]; .name == $host and .runtime.state == "observed" and .runtime.last_seen != null and .runtime.freshness != null)'
        post_check_json "Pharos runtime liveness is not down" "PHAROS-29/pharos-beacon" "$pharos_json" \
            --arg host "$host" 'any(.declared_hosts[]; .name == $host and (.runtime.liveness == "live" or .runtime.liveness == "stale"))'
    else
        post_fail "Pharos declared-hosts endpoint responds" "PHAROS-29"
    fi

    section "HostDash"
    if [[ ! -s "$generated_json" ]]; then
        post_skip "HostDash URL checks" "generated manifest unavailable"
    else
        local key access_host url
        for key in $(post_context_keys "$context"); do
            access_host="$(jq -r --arg key "$key" '.host.access[$key] // empty' "$generated_json")"
            if [[ -z "$access_host" ]]; then
                post_skip "HostDash $key URL" "no host.access.$key in manifest"
                continue
            fi
            url="http://${access_host}/"
            if curl -fsS -m 8 -o /dev/null "$url" 2>/dev/null; then
                post_pass "HostDash $key URL responds"
            else
                post_fail "HostDash $key URL responds" "HOSTD/NIX networking"
                continue
            fi
            if curl -fsS -m 8 "${url}manifest.json" >"$served_manifest" 2>/dev/null; then
                post_pass "HostDash $key manifest endpoint responds"
                if diff -u <(jq -S . "$generated_json") <(jq -S . "$served_manifest") >/dev/null; then
                    post_pass "HostDash $key served manifest matches nixcfg"
                else
                    post_fail "HostDash $key served manifest matches nixcfg" "HOSTD-4/NIX-279"
                fi
            else
                post_fail "HostDash $key manifest endpoint responds" "HOSTD-4"
            fi
        done
    fi

    local total
    total=$((POST_PASS + POST_FAIL + POST_SKIP))
    echo ""
    if [[ $POST_FAIL -eq 0 ]]; then
        echo "${GREEN}${BOLD}✓ inspr post-deploy: validation passed${RESET} (${POST_PASS}/${total}, ${POST_SKIP} skipped)"
        exit 0
    else
        echo "${RED}${BOLD}✗ inspr post-deploy: ${POST_FAIL} check(s) failed${RESET} (${POST_PASS}/${total}, ${POST_SKIP} skipped)"
        exit 1
    fi
}

# ── main dispatch ───────────────────────────────────────────────────────────

# No args → help
if [[ $# -eq 0 ]]; then
    cmd_help
    exit 0
fi

# First arg is either a sub-command or a flag
case "$1" in
-h | --help)
    cmd_help
    exit 0
    ;;
--version)
    cmd_version
    exit 0
    ;;
--vision)
    cmd_vision
    exit $?
    ;;
check)
    shift
    cmd_check "$@"
    ;;
heal)
    shift
    cmd_heal "$@"
    ;;
onboard)
    shift
    cmd_onboard "$@"
    ;;
post-deploy)
    shift
    cmd_post_deploy "$@"
    ;;
*)
    echo "${RED}error:${RESET} unknown command or flag: '$1' (try ${CYAN}inspr --help${RESET})" >&2
    exit 2
    ;;
esac
