# Step 2: CSR（証明書署名要求）の生成と公開鍵の仕組み

Step 1 では学習用に `-x509` オプションで自己署名証明書を直接作りましたが、実運用（プライベートCAや商用CAから証明書を発行してもらう場合）では、まず **CSR（Certificate Signing Request：証明書署名要求）** を作成して認証局へ提出します。

---

## 1. CSR の役割と内部構造

### なぜ秘密鍵ではなく CSR を送るのか？

サーバーの秘密鍵（`certs/private.key`）は絶対に外部へ出してはいけません。CSR には次の 2 つの重要な役割があります。

1. **公開鍵と申請者情報の伝達**: 証明書に埋め込む「公開鍵」と「Subject（ドメイン名・組織名など）」を認証局へ正確に伝える。
2. **秘密鍵の所有証明（Proof of Possession）**: CSR の末尾には申請者自身の秘密鍵で作った電子署名が付与されている。認証局は CSR 内の公開鍵でこの署名を検証し、「ペアとなる秘密鍵を正当に保有している本人である」ことを確認する。

### CSR（PKCS#10 / RFC 2986）の3要素

- `certificationRequestInfo`（申請情報本体）: バージョン、Subject、公開鍵（`SubjectPublicKeyInfo`）、拡張属性
- `signatureAlgorithm`: 署名アルゴリズム（例: `sha256WithRSAEncryption`）
- `signature`: 申請情報本体のハッシュ値を申請者の秘密鍵で署名したデータ

> **注意**: 有効期限（`Validity`）や発行者（`Issuer`）は CSR には含まれません。これらは認証局側が審査・承認したあとに決定して証明書へ書き込む項目だからです。

---

## 2. CSR の生成と署名検証

Step 1 で作成した秘密鍵 `certs/private.key` を使って CSR を作成します（`-x509` を外して `-new` にします）。

### 2.1 CSR を生成する

ここでは例として、予約済みテスト用TLD（`.test`）を使った `CN = dev.ai-nexus.test` の CSR を作成します（Step 4 で SAN に `localhost` や `127.0.0.1` も追加して署名します）。

```bash
openssl req -new -key certs/private.key -out certs/server.csr \
  -subj "/C=JP/ST=Tokyo/L=Example-ku/O=AI Nexus (DEV)/OU=Local Development/CN=dev.ai-nexus.test"
```

1行目のヘッダが `-----BEGIN CERTIFICATE REQUEST-----` になっていることを確認しましょう。

```bash
head -n 3 certs/server.csr
```

### 2.2 CSR の中身と署名の正当性を検証する

```bash
openssl req -in certs/server.csr -text -noout -verify
```

- `-verify`: CSR 内の公開鍵で末尾の電子署名を検証します。成功すると出力の先頭に `Certificate request self-signature verify OK` と表示されます。

---

## 3. 出力のどこが「公開鍵」なのか？

`openssl req -in certs/server.csr -text -noout` を実行すると、`Subject Public Key Info:` ブロックが表示されます。

```text
Subject Public Key Info:
    Public Key Algorithm: rsaEncryption
        Public-Key: (2048 bit)
        Modulus:
            00:d2:87:eb:de:1f:a7:...（中略）...   <-- ① 公開鍵の本体（2048ビットの整数 N）
        Exponent: 65537 (0x10001)                  <-- ② 公開指数（固定的に使われる整数 e）
```

RSA 暗号の公開鍵は、数学的に **「法（Modulus: $N$）」** と **「公開指数（Exponent: $e$）」** という 2 つの大きな整数のペア $(N, e)$ で構成されています。

1. **Modulus ($N$)**: 秘密鍵側に保存されている 2 つの巨大な素数 ($p$ と $q$) を掛け合わせて作られた 2048 ビット（256 バイト）の整数を 16 進数で表したもの。実質的な公開鍵の固有データです。
2. **Exponent ($e$)**: 暗号化や署名検証のべき乗剰余演算に使う指数。計算効率と安全性のバランスから、現在ではほぼすべての RSA 鍵で `65537`（16進数で `0x10001`）が標準的に使われます。

> **他のブロックとの違い**: 一番下にある `Signature Value` は公開鍵ではなく、`Data:` ブロック全体のハッシュ値を秘密鍵で署名した「電子署名」のデータです。

---

## 4. 公開鍵だけを PEM 形式で取り出して比較する

`certs/server.csr` と `certs/private.key` のそれぞれから純粋な公開鍵だけを抜き出して、まったく同一の公開鍵になっていることを確認してみましょう。

```bash
# CSR から公開鍵を取り出す
openssl req -in certs/server.csr -pubkey -noout > certs/public_from_csr.key

# 秘密鍵から公開鍵を導出する
openssl rsa -in certs/private.key -pubout -out certs/public_from_priv.key

# 中身を表示して一致確認
cat certs/public_from_csr.key
diff -u certs/public_from_csr.key certs/public_from_priv.key && echo "完全に一致しました"
```

---

[← Step 1: 自己署名証明書](01_self_signed.md) | [次へ: Step 3 簡易HTTPSサーバーで体験 →](03_https_test.md)
