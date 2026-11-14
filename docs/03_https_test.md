# Step 3: 簡易 HTTPS サーバーで自己署名証明書の挙動を体験する

Step 1 で作成した自己署名証明書（`certs/cert.crt`）と秘密鍵（`certs/private.key`）を使って、ローカルで HTTPS サーバーを起動し、`curl` やブラウザが自己署名証明書をどう扱うかを体験します。

---

## 1. Python 簡易 HTTPS サーバーの起動

このリポジトリに含まれる `https_server.py` は Python 標準ライブラリ（`http.server`, `ssl`）のみで動作し、`index.html` を HTTPS（デフォルトポート `8443`）で配信します。

**ターミナル1** で以下を実行してサーバーを起動してください（このターミナルは起動したままにしておきます）。

```bash
python3 https_server.py --cert certs/cert.crt --key certs/private.key
```

`Serving HTTPS on https://localhost:8443` と表示されれば起動成功です。

> **補足**: `https_server.py` のデフォルト引数は `--cert certs/cert.crt --key certs/private.key` になっているため、引数を省略して `python3 https_server.py` だけでも起動します。また、実験中に誤って秘密鍵が配信されないよう、`/index.html` 以外のパス（`certs/` や `*.key` 等）への HTTP アクセスは `403 Forbidden` でブロックされます。

---

## 2. `curl` コマンドで検証挙動を比較する

別のターミナル（**ターミナル2**）を開き、3 つのパターンでアクセス結果の違いを体験します。

### パターンA: そのままアクセスする（検証エラーの体験）

```bash
curl -v https://localhost:8443
```

**期待される結果**:
`SSL certificate problem: self-signed certificate` というエラーが出て接続が拒否されます。OS の信頼リストに存在しない自己署名証明書のため、`curl` が通信をブロックします。

### パターンB: `certs/cert.crt` を信頼する証明書として明示的に渡す（成功の体験）

```bash
curl -v --cacert certs/cert.crt https://localhost:8443
```

**期待される結果**:
TLS ハンドシェイク（`SSL connection using TLSv1.3` など）が成功し、`index.html` の HTML が返ってきます。

> **もしホスト名不一致エラーが出たら？**
> Step 1 で証明書を作成した際、Common Name (`CN`) に `localhost` 以外を入力していた場合は、`--cacert` を渡してもホスト名不一致エラーになります。その場合は `-k`（検証スキップ）で通信内容だけ確認できます。
> ```bash
> curl -v -k https://localhost:8443
> ```
> ※ `-k` は中間者攻撃を防げないため、本番環境では使用しません。ホスト名問題の根本解決（**SAN の付与**）は次の Step 4 で行います。

---

## 3. ブラウザでアクセスして警告画面を体験する

同じ PC 上のブラウザ（Chrome / Edge / Firefox など）で次の URL を開きます。

```text
https://localhost:8443
```

1. **赤い警告画面**（「この接続ではプライバシーが保護されません / `ERR_CERT_AUTHORITY_INVALID`」）が表示されることを確認します。
2. 画面左下の「詳細設定」＞「`localhost` にアクセスする（安全ではありません）」をクリックすると警告を通過して `index.html` を表示できます。
3. アドレスバーのアイコン（「保護されていない通信」や証明書情報）を開くと、自分が Step 1 で作成した `certs/cert.crt` の Subject / Issuer / 公開鍵をブラウザ上でも確認できます。

---

## 4. サーバーを停止する

確認が終わったら、**ターミナル1** で `Ctrl + C` を押してサーバーを停止してください。

### ここまでの課題と次のステップ

自己署名証明書 1 枚だけでは次の課題が残ります。

- 新しいサーバー証明書を増やすたびに、毎回すべての端末に証明書を配り直す必要がある
- 現代のブラウザやクライアントは **CN ではなく SAN（Subject Alternative Name）** を必須とする

次の Step 4 では、**独自のプライベートCA（ルートCA）** を構築し、Step 2 の `certs/server.csr` に対して **SAN 付きサーバー証明書** を署名・発行します。

---

[← Step 2: CSRと公開鍵の仕組み](02_csr_and_keys.md) | [次へ: Step 4 プライベートCAとSAN証明書 →](04_private_ca.md)
