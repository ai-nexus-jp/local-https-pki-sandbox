# デジタル証明書・プライベートCA・ローカルHTTPS ハンズオンチュートリアル

このプロジェクトは、**OpenSSL**・**Python標準ライブラリ**・**OS/ブラウザの信頼ストア**・**mkcert** を使って、デジタル証明書の仕組みからローカルHTTPS通信の検証までを **一から順番に手を動かして理解する** ためのハンズオンチュートリアルです。

## このチュートリアルで学べること

1. **自己署名証明書（オレオレ証明書）の発行と構造** — PEM / DER形式、ASN.1構造、公開情報と秘密鍵の境界
2. **CSR（証明書署名要求）と公開鍵の正体** — Proof of Possession、Modulus (`N`) と Exponent (`e`)
3. **簡易HTTPSサーバーでの通信体験** — `curl` やブラウザで発生する信頼エラーと回避・検証の違い
4. **プライベートCA（ルートCA）の構築とSAN付き証明書の発行** — 信頼チェーンと `subjectAltName` が必須な理由
5. **OS / ブラウザの信頼ストア登録とクリーンアップ** — Ubuntu (`update-ca-certificates`) と NSS DB (`certutil`) への登録・削除
6. **`mkcert` による実用的なローカルHTTPS開発環境** — 開発プロジェクトでの自動化手法

---

## ディレクトリ構成

```text
certs_dev/
├── README.md                 # このガイド（全体目次）
├── .gitignore                # 秘密鍵や証明書 (*.key, *.crt, certs/ 等) をGitから除外
├── docker-compose.yml        # Step 5 用: ホストを汚さない Docker 隔離検証環境
├── docker/
│   └── Dockerfile.client     # Step 5 用: Ubuntu クライアントコンテナ定義
├── https_server.py           # 学習用簡易HTTPSサーバー（Python標準ライブラリのみ）
├── index.html                # HTTPSアクセス確認用テストページ
├── configs/
│   ├── ca.cnf.example        # Step 4 で使用する AI Nexus DEV ルートCA設定（Name Constraints付き）
│   └── san.ext.example       # Step 4 で使用する SAN (Subject Alternative Name) 設定雛形
├── docs/
│   ├── 00_setup.md           # Step 0: 環境確認とプロジェクト準備
│   ├── 01_self_signed.md     # Step 1: 自己署名証明書の発行・PEM/DER・ASN.1構造
│   ├── 02_csr_and_keys.md    # Step 2: CSRの役割・署名検証・公開鍵の抽出
│   ├── 03_https_test.md      # Step 3: HTTPSサーバーで警告画面とcurlエラーを体験
│   ├── 04_private_ca.md      # Step 4: プライベートCA構築とSAN付きサーバー証明書の発行
│   ├── 05_trust_store.md     # Step 5: Docker隔離環境での信頼ストア登録とブラウザ検証
│   └── 06_mkcert.md          # Step 6: (参考) mkcertを使ったローカルHTTPS環境の構築
├── scripts/
│   ├── check_env.sh          # 必要ツールのインストール状況チェック
│   ├── reset_certs.sh        # certs/ ディレクトリを初期化して最初からやり直す
│   └── verify_tutorial.sh    # Step 1〜4 の動作を一時ディレクトリで自動検証
└── certs/                    # （作業中に作成）チュートリアルで生成する鍵・証明書一式
```

---

## クイックスタート

まずは環境チェックを実行して、必要なコマンド（`openssl`, `python3`, `curl` など）が揃っているか確認してください。

```bash
./scripts/check_env.sh
```

動作確認が完了したら、**Step 0** から順に進めてください。

| ステップ | 内容 | 主なコマンド・技術 |
| :--- | :--- | :--- |
| [Step 0: 事前準備と構成理解](docs/00_setup.md) | フォルダ構成、`.gitignore`、前提確認 | `mkdir certs`, `check_env.sh` |
| [Step 1: 自己署名証明書の発行と構造](docs/01_self_signed.md) | 自己署名証明書生成、PEM/DER、ASN.1解析 | `openssl req -x509`, `x509`, `asn1parse` |
| [Step 2: CSRと公開鍵の仕組み](docs/02_csr_and_keys.md) | CSR生成、署名検証、Modulus/Exponent、公開鍵抽出 | `openssl req -new`, `-verify`, `-pubkey` |
| [Step 3: 簡易HTTPSサーバーで体験](docs/03_https_test.md) | Python HTTPS起動、`curl`・ブラウザの警告体験 | `python3 https_server.py`, `curl` |
| [Step 4: プライベートCAとSAN証明書](docs/04_private_ca.md) | ルートCA作成、`san.ext` 付与、チェーン検証 | `openssl genrsa`, `x509 -req`, `verify` |
| [Step 5: Docker隔離環境での信頼ストア登録](docs/05_trust_store.md) | ホストを汚さずコンテナ内OS・ブラウザで検証＆破棄 | `docker compose`, `update-ca-certificates`, noVNC |
| [Step 6: (参考) mkcertによる開発環境自動化](docs/06_mkcert.md) | 開発用プライベートCAと証明書の自動設定 | `mkcert -install`, `mkcert` |

---

## やり直し・動作確認用スクリプト

- **最初からやり直したいとき**:
  ```bash
  ./scripts/reset_certs.sh
  ```
  `certs/` 内の生成ファイルを空にします（Step 5 でシステム・ブラウザに登録したCAの削除は `docs/05_trust_store.md` のクリーンアップ手順を参照してください）。

- **Step 1〜4 の一連の動作をまとめて検証したいとき**（作業中の `certs/` を汚さず一時領域で検証します）:
  ```bash
  ./scripts/verify_tutorial.sh
  ```
