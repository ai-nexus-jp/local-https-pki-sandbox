# Step 6: （参考）`mkcert` を使った開発用ローカル HTTPS 環境の自動構築

Step 1〜5 では OpenSSL を使って手作業で「プライベートCA構築 → CSR署名 → SAN設定 → Docker 隔離環境での信頼ストア登録」を一通り実践しました。
実際の個人開発やローカル開発プロジェクトで手早く自分のPC（ホスト環境）に HTTPS 環境を用意したい場合は、これらを自動で行ってくれる開発支援ツール **`mkcert`** がよく使われます。

> **注意**: `mkcert -install` はホストPCの信頼ストアにローカルCAを登録します。ホスト環境を汚したくない場合は、このページは「実務でよく使われる自動化ツールの知識」として読むだけにとどめ、テストは Step 5 の Docker 環境で行うのが安全です。

---

## 1. `mkcert` とは？

`mkcert` は、ローカル端末内に「独自のプライベート認証局（CA）」を自動構築し、OS および各ブラウザの信頼ストアへルート証明書を自動登録した上で、SAN 付きのサーバー証明書を 1 コマンドで発行してくれるツールです。

---

## 2. インストール手順

### Linux（Ubuntu / Debian 系）

ブラウザの証明書ストア操作のため `libnss3-tools` を入れてからバイナリを配置します。

```bash
# 依存パッケージのインストール
sudo apt update && sudo apt install -y libnss3-tools

# mkcert バイナリのダウンロードと配置（x86_64 環境の例）
curl -JLO "https://dl.filippo.io/mkcert/latest?for=linux/amd64"
chmod +x mkcert-v*-linux-amd64
sudo mv mkcert-v*-linux-amd64 /usr/local/bin/mkcert

# バージョン確認
mkcert -version
```

### macOS（Homebrew）

```bash
brew install mkcert
brew install nss  # Firefox でも警告を出さないようにする場合
```

### Windows（Chocolatey / Scoop）

```powershell
# Chocolatey
choco install mkcert

# Scoop
scoop bucket add extras
scoop install mkcert
```

---

## 3. 使い方（証明書の発行からサーバー適用まで）

### 3.1 初回のみ：ローカルCAの作成と OS / ブラウザへの登録

```bash
mkcert -install
```

作成されたルート証明書（`rootCA.pem`）と秘密鍵（`rootCA-key.pem`）の保存先は以下で確認できます。

```bash
mkcert -CAROOT
```

### 3.2 サーバー証明書と秘密鍵の発行

検証で使いたいドメイン名や IP アドレスを指定して `certs/` 配下に出力します。

```bash
mkcert -cert-file certs/mkcert.crt -key-file certs/mkcert.key localhost 127.0.0.1 ::1
```

（オプションを省略して `mkcert localhost 127.0.0.1 ::1` を実行すると、`localhost+2.pem` と `localhost+2-key.pem` が生成されます。）

### 3.3 `https_server.py` で動作確認

```bash
python3 https_server.py --cert certs/mkcert.crt --key certs/mkcert.key
```

別ターミナルからの `curl -v https://localhost:8443` やブラウザアクセスが、追加設定なしで信頼済みとして成功することを確認できます。

---

## 4. セキュリティ上の注意点とアンインストール

- **`rootCA-key.pem` は絶対に共有・流出させない**: `mkcert -CAROOT` のディレクトリにある秘密鍵が第三者に渡ると、あなたのPCやブラウザが正規のサイトとして信頼する偽の証明書を自由に作られてしまいます。チーム共有する場合でも `rootCA.pem` のみにとどめ、通常は各自のローカルPCで `mkcert -install` を実行します。
- **検証が不要になったときの削除**:
  ```bash
  mkcert -uninstall
  ```
  これで OS・ブラウザの信頼ストアから `mkcert` のルート証明書を安全に削除できます。

---

[← Step 5: OS・ブラウザの信頼ストア登録](05_trust_store.md) | [README に戻る →](../README.md)
