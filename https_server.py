"""学習・検証用の簡易 HTTPS サーバー。

自己署名証明書やプライベートCAで署名したサーバー証明書を読み込み、
ローカル環境で HTTPS (TLS) 通信の挙動を確認するために使用する。
秘密鍵や証明書ディレクトリへの HTTP 経由アクセスはブロックする。
"""

import argparse
import http.server
import ssl
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent


class SafeTutorialHTTPRequestHandler(http.server.SimpleHTTPRequestHandler):
    """チュートリアル用の静的ファイル配信ハンドラ（秘密鍵等の露出を防止）。"""

    BLOCKED_SUFFIXES = (".key", ".pem", ".crt", ".csr", ".der", ".srl", ".ext")

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(BASE_DIR), **kwargs)

    def _is_blocked_path(self) -> bool:
        req_path = self.path.split("?", 1)[0].split("#", 1)[0]
        normalized = Path(req_path.lstrip("/"))
        parts = normalized.parts
        if "certs" in parts or ".git" in parts or ".agents" in parts:
            return True
        if req_path.endswith(self.BLOCKED_SUFFIXES):
            return True
        # ルート直下のディレクトリ一覧表示を防ぎ、index.html のみ許可
        if req_path not in ("/", "/index.html"):
            return True
        return False

    def do_GET(self):
        if self._is_blocked_path():
            self.send_error(403, "Forbidden: this tutorial server only serves /index.html")
            return
        super().do_GET()

    def do_HEAD(self):
        if self._is_blocked_path():
            self.send_error(403, "Forbidden: this tutorial server only serves /index.html")
            return
        super().do_HEAD()


def run_server(host: str, port: int, certfile: str, keyfile: str) -> None:
    """指定された証明書と秘密鍵で HTTPS サーバーを起動する。"""
    cert_path = Path(certfile)
    key_path = Path(keyfile)
    if not cert_path.is_file() or not key_path.is_file():
        print(
            f"Error: 証明書または秘密鍵が見つかりません (cert: {certfile}, key: {keyfile})\n"
            "先にチュートリアルの手順に従って証明書を作成するか、--cert / --key でパスを指定してください。",
            file=sys.stderr,
        )
        sys.exit(1)

    server_address = (host, port)
    httpd = http.server.ThreadingHTTPServer(server_address, SafeTutorialHTTPRequestHandler)

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile=str(cert_path), keyfile=str(key_path))
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

    print(f"Serving HTTPS on https://localhost:{port} (bind: {host}:{port})")
    print(f"  Certificate : {cert_path}")
    print(f"  Private Key : {key_path}")
    print("Press Ctrl+C to stop.")

    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        httpd.server_close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Simple HTTPS Server for Certificate Tutorial")
    parser.add_argument("--host", default="0.0.0.0", help="Bind address (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8443, help="Port number (default: 8443)")
    parser.add_argument("--cert", default="certs/cert.crt", help="Path to certificate file (default: certs/cert.crt)")
    parser.add_argument("--key", default="certs/private.key", help="Path to private key file (default: certs/private.key)")

    args = parser.parse_args()
    run_server(args.host, args.port, args.cert, args.key)
