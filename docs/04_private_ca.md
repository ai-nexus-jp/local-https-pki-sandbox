# Step 4: プライベートCA（ルートCA）構築と SAN 付きサーバー証明書の発行

このステップでは、Step 2 で作成した `certs/server.csr` に対して、**AI Nexus 開発用のプライベート認証局（ルートCA）** を立てて署名し、**SAN（Subject Alternative Name）** 付きのサーバー証明書 `certs/server.crt` を発行します。

さらに、このテスト用ルートCAには **「誰かの端末に入れても実在の外部サイトには絶対に使えない」** よう、**`Name Constraints`** と **短めの有効期限（1ヶ月）** を設定します。

---

## 1. 安全な DEV 用プライベートCA（ルートCA）の構築

### 1.1 CA 用の秘密鍵（`certs/ca.key`）を生成する

```bash
openssl genrsa -out certs/ca.key 4096
```

※ ルートCAの鍵は高信頼用途のため 4096 ビットで生成します（学習・検証用としてパスフレーズなし）。

### 1.2 CA 設定ファイル（`certs/ca.cnf`）を用意する

`configs/ca.cnf.example` を `certs/ca.cnf` へコピーし、中身を確認します。

```bash
cp configs/ca.cnf.example certs/ca.cnf
cat certs/ca.cnf
```

ここには次の **2 つの安全設計** が入っています：

1. **一目で DEV 用とわかる識別名（Subject）**:
   - `O = AI Nexus (DEV)` / `OU = Local Development PKI` / `CN = AI Nexus DEV Root CA`
   - ブラウザや OS の証明書マネージャの一覧で「本番CA」と絶対に混同しない名前にしています。
2. **`Name Constraints`（名前制約）による技術的な封じ込め**:
   ```ini
   [name_constraints]
   permitted;DNS.0 = test
   permitted;DNS.1 = localhost
   permitted;IP.0 = 127.0.0.1/255.255.255.255
   permitted;IP.1 = ::1/ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff
   ```
   - これにより、このルートCAは **`.test` ドメイン（例: `dev.ai-nexus.test`）・`localhost`・ループバックIP（`127.0.0.1` / `::1`）の証明書にしか使えない** よう暗号プロトコルレベルで制限されます。
   - 万が一この `ca.crt` が誰かの端末に登録されていても、実在の外部ドメイン（例: `example.com` や銀行サイト等）の偽証明書を信頼させることはできません。
   - ※ `DNS:test` のように先頭ドットなしで指定するのが RFC 5280 準拠の書き方で、`test` およびすべてのサブドメイン（`dev.ai-nexus.test` など）に一致します。

### 1.3 CA 用のルート証明書（`certs/ca.crt`）を発行する

`openssl req -x509` に `-config certs/ca.cnf` を渡してルート証明書を発行します。学習・検証用として有効期間は **1ヶ月（`-days 30`）** に設定しています（長期の開発で延長したい場合は `-days 365` 等へ任意に伸ばせます）。

```bash
openssl req -x509 -new -nodes -key certs/ca.key -sha256 -days 30 \
  -out certs/ca.crt -config certs/ca.cnf
```

> **確認**: `openssl x509 -in certs/ca.crt -text -noout` を実行すると、以下が確認できます。
> - `Issuer` / `Subject` が `O = AI Nexus (DEV), OU = Local Development PKI, CN = AI Nexus DEV Root CA`
> - `X509v3 Basic Constraints: critical` が `CA:TRUE`
> - `X509v3 Name Constraints: critical` の `Permitted` に `DNS:test`, `DNS:localhost`, IP が並んでいる

---

## 2. SAN（Subject Alternative Name）設定ファイルの作成

現代の TLS 検証（Chrome, Firefox, curl, Go など）では、証明書の **CN（Common Name）だけではドメイン一致とみなされず、拡張領域の `subjectAltName`（SAN）の記載が必須** となっています。

このリポジトリの `configs/san.ext.example` を `certs/san.ext` にコピーして使用します。

```bash
cp configs/san.ext.example certs/san.ext
cat certs/san.ext
```

```ini
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = dev.ai-nexus.test
DNS.2 = localhost
IP.1 = 127.0.0.1
IP.2 = ::1
```

- `basicConstraints=CA:FALSE`: この証明書が別の証明書に署名する CA ではなく、末端のサーバー証明書であることを明示する。
- `[alt_names]`: 接続を許可するホスト名（DNS）と IP アドレスを列挙する（`dev.ai-nexus.test` に加え、ローカル検証用の `localhost`・`127.0.0.1`・`::1` を含めています）。

---

## 3. `server.csr` にルートCAの秘密鍵で署名して発行する

用意した `certs/ca.crt`・`certs/ca.key`・`certs/san.ext` を使って、`certs/server.csr` に署名し `certs/server.crt` を生成します。有効期限はルートCAと同様に 1ヶ月（`-days 30`、任意で延長可）にしています。

```bash
openssl x509 -req -in certs/server.csr \
  -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -out certs/server.crt -days 30 -sha256 -extfile certs/san.ext
```

| オプション | 意味 |
| :--- | :--- |
| `-req -in certs/server.csr` | 入力が CSR であることを指定 |
| `-CA` / `-CAkey` | 署名に使用するルートCAの証明書と秘密鍵 |
| `-CAcreateserial` | 発行する証明書のシリアル番号を管理する `certs/ca.srl` を自動生成 |
| `-days 30` | サーバー証明書の有効期限（1ヶ月。必要に応じて `-days 365` 等へ変更可） |
| `-extfile certs/san.ext` | SAN や基本制約などの X.509 v3 拡張属性を証明書へ埋め込む |

---

## 4. 発行された証明書と信頼チェーンの検証

### 4.1 証明書の内容（Issuer と SAN）を確認する

```bash
openssl x509 -in certs/server.crt -text -noout
```

以下を確認してください。
- **`Issuer`** が `O = AI Nexus (DEV), ..., CN = AI Nexus DEV Root CA` になり、**`Subject`** が `CN = dev.ai-nexus.test` になっている。
- **`X509v3 Basic Constraints`** が `CA:FALSE` になっている。
- **`X509v3 Subject Alternative Name`** に `DNS:dev.ai-nexus.test, DNS:localhost, IP Address:127.0.0.1, IP Address:0:0:0:0:0:0:0:1` が記載されている。

### 4.2 ルートCAを使ってサーバー証明書の署名を検証する

```bash
openssl verify -CAfile certs/ca.crt certs/server.crt
```

`certs/server.crt: OK` と出力されれば、CA の公開鍵による電子署名の検証および `Name Constraints` のチェックが正常に通過しています。

### 4.3 （おまけ確認）許可外ドメインの証明書は本当に拒否されるか？

もし `ca.key` で誤って `.test` 以外のドメイン（例: `evil.example.com`）に署名してしまった場合でも、`Name Constraints` によって検証時に弾かれることを確かめられます。

```bash
openssl req -new -key certs/private.key -out certs/bad.csr \
  -subj "/C=JP/ST=Tokyo/O=Evil/CN=evil.example.com"
printf "basicConstraints=CA:FALSE\nsubjectAltName=DNS:evil.example.com\n" > certs/bad.ext
openssl x509 -req -in certs/bad.csr -CA certs/ca.crt -CAkey certs/ca.key \
  -CAcreateserial -out certs/bad.crt -days 30 -sha256 -extfile certs/bad.ext
openssl verify -CAfile certs/ca.crt certs/bad.crt
```

`error 47 at 0 depth lookup: permitted subtree violation` となり、**検証が失敗すること**を確認できます（確認後は `rm -f certs/bad.csr certs/bad.ext certs/bad.crt` で消しておきましょう）。

---

## 5. `https_server.py` を `server.crt` に切り替えて確認する

サーバー側を Step 4 で発行した `certs/server.crt` に切り替えて起動します。

**ターミナル1**:
```bash
python3 https_server.py --cert certs/server.crt --key certs/private.key
```

**ターミナル2**:
今度はサーバー証明書そのものではなく、**ルートCA証明書（`certs/ca.crt`）** を信頼対象として `curl` に渡します。

```bash
curl -v --cacert certs/ca.crt https://localhost:8443
```

`server.crt` を直接渡さなくても、`ca.crt` からの信頼チェーンと SAN (`DNS:localhost`) が一致するため、検証が通り HTML が返ってきます！

確認が終わったらターミナル1のサーバーを `Ctrl + C` で停止してください。次の Step 5 では、ホスト PC を汚さずに Docker 上で `https://dev.ai-nexus.test:8443` へアクセスして信頼ストアの挙動を体験します。

---

[← Step 3: 簡易HTTPSサーバーで体験](03_https_test.md) | [次へ: Step 5 Docker隔離環境での信頼ストア登録 →](05_trust_store.md)
