#!/usr/bin/env bash
set -euo pipefail

# チュートリアル Step 1 〜 Step 4 の手順が一通り動作することを
# 一時ディレクトリ上で非破壊検証するスクリプト。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

TMP_DIR="$(mktemp -d)"
SERVER_PID=""

cleanup() {
  if [ -n "$SERVER_PID" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

PORT=18443

echo "[Step 1] 自己署名証明書 (cert.crt, private.key) の生成と検証..."
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout "$TMP_DIR/private.key" \
  -out "$TMP_DIR/cert.crt" \
  -days 365 \
  -subj "/C=JP/ST=Tokyo/L=Example-ku/O=dev/CN=localhost" >/dev/null 2>&1
openssl x509 -in "$TMP_DIR/cert.crt" -outform der -out "$TMP_DIR/cert.der"
openssl asn1parse -in "$TMP_DIR/cert.crt" >/dev/null

echo "[Step 2] CSR (server.csr) の生成・署名検証・公開鍵抽出..."
openssl req -new -key "$TMP_DIR/private.key" \
  -out "$TMP_DIR/server.csr" \
  -subj "/C=JP/ST=Tokyo/L=Example-ku/O=AI Nexus (DEV)/OU=Local Development/CN=dev.ai-nexus.test" >/dev/null 2>&1
openssl req -in "$TMP_DIR/server.csr" -noout -verify >/dev/null 2>&1
openssl req -in "$TMP_DIR/server.csr" -pubkey -noout > "$TMP_DIR/public_from_csr.key"
openssl rsa -in "$TMP_DIR/private.key" -pubout -out "$TMP_DIR/public_from_priv.key" 2>/dev/null
diff -u "$TMP_DIR/public_from_csr.key" "$TMP_DIR/public_from_priv.key"

echo "[Step 3] 自己署名証明書で https_server.py を起動し curl 検証..."
python3 "$ROOT_DIR/https_server.py" \
  --host 127.0.0.1 --port "$PORT" \
  --cert "$TMP_DIR/cert.crt" --key "$TMP_DIR/private.key" >/dev/null 2>&1 &
SERVER_PID=$!

# サーバーの起動待ち
for _ in $(seq 1 20); do
  if curl -s -k "https://localhost:$PORT/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

# 信頼していない自己署名証明書は失敗する（curl exit code 60）
if curl -sS "https://localhost:$PORT/" >/dev/null 2>&1; then
  echo "ERROR: 未信頼の自己署名証明書へのアクセスが失敗するはずが成功しました" >&2
  exit 1
fi

# --cacert cert.crt で成功する
STATUS_SELF="$(curl -sS --cacert "$TMP_DIR/cert.crt" -o /dev/null -w "%{http_code}" "https://localhost:$PORT/")"
if [ "$STATUS_SELF" != "200" ]; then
  echo "ERROR: --cacert cert.crt での HTTP ステータスが 200 ではありません: $STATUS_SELF" >&2
  exit 1
fi

# 秘密鍵へのHTTPアクセスがブロックされること（403）
STATUS_FORBIDDEN="$(curl -sS --cacert "$TMP_DIR/cert.crt" -o /dev/null -w "%{http_code}" "https://localhost:$PORT/certs/private.key")"
if [ "$STATUS_FORBIDDEN" != "403" ]; then
  echo "ERROR: ブロック対象パスへのHTTPステータスが 403 ではありません: $STATUS_FORBIDDEN" >&2
  exit 1
fi

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
SERVER_PID=""

echo "[Step 4] プライベートCA構築 (Name Constraints付き) とSAN付きサーバー証明書 (server.crt) の発行・検証..."
openssl genrsa -out "$TMP_DIR/ca.key" 4096 2>/dev/null
cp "$ROOT_DIR/configs/ca.cnf.example" "$TMP_DIR/ca.cnf"
openssl req -x509 -new -nodes -key "$TMP_DIR/ca.key" -sha256 -days 30 \
  -out "$TMP_DIR/ca.crt" -config "$TMP_DIR/ca.cnf" >/dev/null 2>&1

cp "$ROOT_DIR/configs/san.ext.example" "$TMP_DIR/san.ext"
openssl x509 -req -in "$TMP_DIR/server.csr" \
  -CA "$TMP_DIR/ca.crt" -CAkey "$TMP_DIR/ca.key" -CAcreateserial \
  -out "$TMP_DIR/server.crt" -days 30 -sha256 -extfile "$TMP_DIR/san.ext" >/dev/null 2>&1

openssl verify -CAfile "$TMP_DIR/ca.crt" "$TMP_DIR/server.crt"

# Name Constraints が許可外ドメイン (evil.example.com) を正しく拒否することを確認
openssl req -new -key "$TMP_DIR/private.key" -out "$TMP_DIR/bad.csr" \
  -subj "/C=JP/ST=Tokyo/O=Evil/CN=evil.example.com" >/dev/null 2>&1
printf "basicConstraints=CA:FALSE\nsubjectAltName=DNS:evil.example.com\n" > "$TMP_DIR/bad.ext"
openssl x509 -req -in "$TMP_DIR/bad.csr" -CA "$TMP_DIR/ca.crt" -CAkey "$TMP_DIR/ca.key" \
  -CAcreateserial -out "$TMP_DIR/bad.crt" -days 30 -sha256 -extfile "$TMP_DIR/bad.ext" >/dev/null 2>&1
if openssl verify -CAfile "$TMP_DIR/ca.crt" "$TMP_DIR/bad.crt" >/dev/null 2>&1; then
  echo "ERROR: Name Constraints が許可外ドメインを拒否できませんでした" >&2
  exit 1
fi
echo "Name Constraints check: evil.example.com rejected as expected."

python3 "$ROOT_DIR/https_server.py" \
  --host 127.0.0.1 --port "$PORT" \
  --cert "$TMP_DIR/server.crt" --key "$TMP_DIR/private.key" >/dev/null 2>&1 &
SERVER_PID=$!

for _ in $(seq 1 20); do
  if curl -s -k "https://localhost:$PORT/" >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done

STATUS_CA="$(curl -sS --cacert "$TMP_DIR/ca.crt" -o /dev/null -w "%{http_code}" "https://localhost:$PORT/")"
if [ "$STATUS_CA" != "200" ]; then
  echo "ERROR: --cacert ca.crt での HTTP ステータスが 200 ではありません: $STATUS_CA" >&2
  exit 1
fi

echo ""
echo "すべての自動検証（Step 1 〜 Step 4）が正常に完了しました！"
