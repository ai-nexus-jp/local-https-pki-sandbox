# Step 1: OpenSSL で自己署名証明書（オレオレ証明書）を発行し、構造を読む

まずは OpenSSL を使って、1コマンドで「秘密鍵の生成」と「自己署名証明書の作成」を行い、デジタル証明書の内部構造（PEM / DER / ASN.1）を確認します。

---

## 1. 自己署名証明書の作成

以下のコマンドを実行して、`certs/private.key`（秘密鍵）と `certs/cert.crt`（自己署名証明書）を生成します。

```bash
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout certs/private.key \
  -out certs/cert.crt \
  -days 365
```

### 各オプションの意味

| オプション | 意味 |
| :--- | :--- |
| `req -x509` | CSR（署名要求）ではなく、X.509 形式の自己署名証明書を直接出力する |
| `-newkey rsa:2048` | 2048ビットの RSA 秘密鍵を新規作成する |
| `-nodes` | 秘密鍵にパスフレーズを設定しない（"No DES" の略。開発・テスト用途向け） |
| `-keyout` | 生成する秘密鍵ファイルの出力先 |
| `-out` | 生成する証明書ファイルの出力先 |
| `-days 365` | 証明書の有効期限（365日） |

### 対話入力の例

実行すると国名やコモンネームの入力を求められます。Step 3 で `https://localhost:8443` にアクセスして確認するため、**Common Name (`CN`) には `localhost`** を入力するのがおすすめです（それ以外は空Enterでも進めます）。

```text
Country Name (2 letter code) [AU]:JP
State or Province Name (full name) [Some-State]:Tokyo
Locality Name (eg, city) []:Example-ku
Organization Name (eg, company) [Internet Widgits Pty Ltd]:dev
Organizational Unit Name (eg, section) []:test
Common Name (e.g. server FQDN or YOUR name) []:localhost
Email Address []:
```

> **ワンライナーでやり直したい場合**（対話入力を `-subj` で省略する例）:
> ```bash
> openssl req -x509 -newkey rsa:2048 -nodes \
>   -keyout certs/private.key -out certs/cert.crt -days 365 \
>   -subj "/C=JP/ST=Tokyo/L=Example-ku/O=dev/OU=test/CN=localhost"
> ```

---

## 2. 生成された2ファイルの役割と取り扱い

| ファイル名 | 役割 | 中身・扱い方 |
| :--- | :--- | :--- |
| `certs/cert.crt` | **デジタル証明書（公開鍵証明書）** | サーバーの公開鍵、所有者情報（Subject）、有効期限、「`private.key` 自身で署名した」電子署名が含まれる。**通信相手（ブラウザ等）に配布してよいファイル。** |
| `certs/private.key` | **秘密鍵** | 証明書とペアになる暗号鍵。TLSハンドシェイク時の署名や復号にサーバー側で使用する。**絶対に外部へ公開・共有してはいけない。** |

---

## 3. 証明書の中身を確認する（公開情報のみ）

`certs/cert.crt` はテキスト形式（PEM形式）ですが、Base64 エンコードされているため人間が読める形式で出力するには `openssl x509` を使います。

```bash
openssl x509 -in certs/cert.crt -text -noout
```

### 確認ポイント

- **`Issuer`（発行者）と `Subject`（所有者）が全く同じ**になっている（＝自分で自分に署名した「自己署名証明書」の証拠）。
- **`Validity`（有効期限）**: Not Before 〜 Not After が365日間になっている。
- **`Subject Public Key Info`**: 2048ビットの RSA 公開鍵（Modulus / Exponent）が埋め込まれている。
- **`Signature Algorithm / Signature Value`**: 改ざん検知用の電子署名データ。

> **この出力に機密情報は含まれる？**
> 一切含まれません。デジタル証明書は通信相手へ提示（公開）する前提のデータであり、公開鍵から秘密鍵を逆算することは数学的に不可能です。画面キャプチャや質問時に共有しても問題ありません。

### 【重要比較】絶対に公開してはいけないコマンド

参考として、秘密鍵側を表示するコマンドもあります。こちらの出力には秘密鍵そのもの（`privateExponent`, `prime1`, `prime2` 等）が含まれるため、**出力結果を絶対に外部へ共有しないでください**。

```bash
# ※ 出力内容は絶対に外部へ出さないこと
openssl rsa -in certs/private.key -text -noout | head -n 10
```

---

## 4. PEM 形式と DER 形式の違い

先ほど生成した `certs/cert.crt` や `certs/private.key` を `cat` で開くと、`-----BEGIN ...-----` で囲まれた文字列になっています。これが **PEM 形式** です。

```bash
head -n 5 certs/cert.crt
head -n 2 certs/private.key
```

### ヘッダを見れば中身の種類がわかる

| 1行目のヘッダ表記 | 中身の種類 | よく使われる拡張子 |
| :--- | :--- | :--- |
| `-----BEGIN CERTIFICATE-----` | デジタル証明書（公開鍵証明書） | `.crt`, `.pem`, `.cer` |
| `-----BEGIN PRIVATE KEY-----` | 秘密鍵（PKCS#8 形式） | `.key`, `.pem` |
| `-----BEGIN RSA PRIVATE KEY-----` | RSA秘密鍵（PKCS#1 形式） | `.key`, `.pem` |
| `-----BEGIN CERTIFICATE REQUEST-----` | 証明書署名要求（CSR） | `.csr`, `.pem` |

> **PEM 形式のメリット**: 複数の証明書（サーバー証明書 ＋ 中間CA証明書など）を1つの `.pem` ファイルに縦に並べて連結できます。

### 対になる「DER 形式」へ変換してみる

中身のデータ構造（ASN.1）は同じで、テキスト（Base64）かバイナリかだけが異なります。

| 比較項目 | PEM 形式 | DER 形式 |
| :--- | :--- | :--- |
| データ形式 | テキスト（Base64エンコード） | バイナリ（0と1の生データ） |
| 主な利用環境 | Linux, OpenSSL, Nginx, Apache, AWS 等 | Windows環境, Java (JKS/PKCS#12周辺) 等 |
| 可読性 | エディタで開ける・コピペ可能 | エディタで開くと文字化けする |

PEM から DER へ変換してファイルサイズを比較してみましょう。

```bash
openssl x509 -in certs/cert.crt -outform der -out certs/cert.der
ls -lh certs/cert.crt certs/cert.der
```

---

## 5. ASN.1 構造を直接覗いてみる

**ASN.1（Abstract Syntax Notation One）** は、OS・言語・CPU（ビッグ/リトルエンディアン等）が異なっても「1ビットの解釈ズレもなく」データ構造を定義するための国際標準スキーマです（JSON Schema や Protocol Buffers の元祖）。

証明書は以下の **3層構造** でファイルになっています。

1. **ASN.1（設計図）**: `SEQUENCE`（構造体）や `INTEGER`、`BIT STRING` などのデータ型定義
2. **DER（バイナリ化ルール）**: ASN.1 の設計図を TLV（Tag-Length-Value）のバイト列にエンコード
3. **PEM（テキスト化ルール）**: DER のバイト列を Base64 化し、`-----BEGIN ...-----` で挟む

`openssl asn1parse` で、実際の証明書の ASN.1 ツリー構造を確認できます。

```bash
openssl asn1parse -in certs/cert.crt
```

`cons: SEQUENCE`（構造体の開始）、`prim: INTEGER`（シリアル番号）、`prim: OBJECT`（アルゴリズム OID）、`prim: UTCTIME`（有効期限）が並んでいる様子が確認できます。

---

[← Step 0: 事前準備](00_setup.md) | [次へ: Step 2 CSRと公開鍵の仕組み →](02_csr_and_keys.md)
