#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CERTS_DIR="$ROOT_DIR/certs"

if [ ! -d "$CERTS_DIR" ]; then
  echo "certs/ ディレクトリはまだ存在しません。リセット不要です。"
  exit 0
fi

if [ "${1:-}" != "--yes" ]; then
  echo "以下のディレクトリ内の生成済み証明書・秘密鍵をすべて削除します:"
  echo "  $CERTS_DIR"
  read -r -p "よろしいですか？ [y/N]: " ans
  case "$ans" in
    y|Y|yes|YES) ;;
    *)
      echo "キャンセルしました。"
      exit 0
      ;;
  esac
fi

rm -rf "$CERTS_DIR"
mkdir -p "$CERTS_DIR"
echo "certs/ を初期化しました。Step 1 からやり直せます。"
