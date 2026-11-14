#!/usr/bin/env bash
set -euo pipefail

echo "=== 環境チェック（証明書・HTTPS検証チュートリアル） ==="
echo ""

check_cmd() {
  local cmd="$1"
  local note="$2"
  if command -v "$cmd" >/dev/null 2>&1; then
    local ver=""
    case "$cmd" in
      openssl) ver="$(openssl version)" ;;
      python3) ver="$(python3 --version)" ;;
      curl)    ver="$(curl --version | head -n 1)" ;;
      docker)  ver="$(docker --version)" ;;
      mkcert)  ver="$(mkcert -version 2>/dev/null || echo 'installed')" ;;
      certutil) ver="installed ($(command -v certutil))" ;;
    esac
    echo "[OK]      $cmd : $ver"
  else
    echo "[MISSING] $cmd : 未インストール ($note)"
  fi
}

check_cmd openssl "必須: sudo apt install -y openssl"
check_cmd python3 "必須: sudo apt install -y python3"
check_cmd curl "必須: sudo apt install -y curl"
check_cmd docker "Step 5 (Docker隔離環境での信頼ストア・ブラウザ検証) で使用"
check_cmd certutil "任意 (ホストに直接登録する場合のみ): sudo apt install -y libnss3-tools"
check_cmd mkcert "Step 6 (参考: mkcert体験) で使用: docs/06_mkcert.md を参照"

if command -v docker >/dev/null 2>&1; then
  if docker compose version >/dev/null 2>&1; then
    echo "[OK]      docker compose : $(docker compose version)"
  else
    echo "[MISSING] docker compose : Docker Compose v2 プラグインが見つかりません"
  fi
fi

echo ""
echo "[INFO] Step 5 は Docker Compose 隔離環境で実行するため、ホストOS・ブラウザの証明書ストアは変更しません。"
