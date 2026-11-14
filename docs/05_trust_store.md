# Step 5: Docker 隔離環境での信頼ストア登録と警告なし HTTPS アクセス

Step 4 では `--cacert certs/ca.crt` を毎回指定して検証を成功させました。
このステップでは、作成したルート証明書（`certs/ca.crt`）を **OS やブラウザの信頼ストア** へ登録し、オプションなし（`curl`）や赤い警告画面なし（ブラウザ）で HTTPS アクセスできることを確認します。

> **なぜホストPCではなく Docker Compose で試すのか？**
> 1. **ホストPCが汚れない**: テスト用のプライベートCA（`certs/ca.key` にパスフレーズがない鍵）をホストOSや普段使いのブラウザに登録したままにするリスクを完全に回避でき、`docker compose down` 一発で破棄できます。
> 2. **「サーバー」と「クライアント」の役割が明確になる**: `docker-compose.yml` では `https-server`（`server.crt` + `private.key`）と `client` / `browser`（`ca.crt` のみ）が別コンテナに分かれています。
> 3. **`dev.ai-nexus.test` を `/etc/hosts` なしで試せる**: Docker ネットワークのエイリアス機能により、Step 2・4 で設定した `dev.ai-nexus.test` へそのままアクセスして SAN の検証までリアルに体験できます。

---

## 0. 事前確認と Docker サンドボックスの起動

### 0.1 証明書ファイルが揃っているか確認

Docker のボリュームマウント時に存在しないファイルがディレクトリとして作られるのを防ぐため、Step 1〜4 で生成したファイルが存在するか確認します。

```bash
ls -l certs/server.crt certs/private.key certs/ca.crt
```

3つのファイルが表示されれば OK です（不足している場合は [Step 4](04_private_ca.md) までを先に完了してください）。

### 0.2 コンテナを起動する

```bash
docker compose up -d --build
```

以下の 3 つのコンテナが起動します。

| サービス名 | 役割 | マウントしている鍵・証明書 |
| :--- | :--- | :--- |
| `https-server` | `https_server.py` を動かすサーバー | `server.crt`, `private.key` のみ（`ca.key` は持たない） |
| `client` | Ubuntu クライアント（`curl` 等） | `ca.crt`（公開情報）のみ |
| `browser` | noVNC 付き Firefox コンテナ | `ca.crt`（公開情報）のみ |

起動状態を確認します。

```bash
docker compose ps
```

---

## 1. Ubuntu クライアントコンテナでの信頼ストア登録（`curl` 検証）

### 1.1 登録前：オプションなしでは失敗することを確認

まずはルートCAを登録していない状態で `client` コンテナから `https://dev.ai-nexus.test:8443` へアクセスします。

```bash
docker compose exec client curl -v https://dev.ai-nexus.test:8443
```

**期待される結果**:
`SSL certificate problem: unable to get local issuer certificate`（または自己署名ルートCA未信頼）で接続が拒否されます。

### 1.2 クライアントコンテナ内のシステム信頼ストアへ `ca.crt` を登録

Ubuntu のシステム信頼ストア（`/usr/local/share/ca-certificates/`）へ配置するときは、拡張子を **`.crt`** にする必要があります。ファイル名も `ai-nexus-dev-ca.crt` としておくと何のCAか一目でわかります。

```bash
docker compose exec client cp /certs/ca.crt /usr/local/share/ca-certificates/ai-nexus-dev-ca.crt
docker compose exec client update-ca-certificates
```

出力に `1 added, 0 removed; done.` と表示されれば、**`client` コンテナ内部だけ** にルート証明書が登録されました。

### 1.3 オプションなしで HTTPS アクセスが成功することを確認

```bash
docker compose exec client curl -v https://dev.ai-nexus.test:8443
```

**期待される結果**:
`--cacert` を付けなくても、`SSL certificate verify ok.` と表示されて `index.html` の内容が返ってきます！

### 1.4 【応用実験】SAN に含まれないホスト名だとどうなるか？

`docker-compose.yml` では、`https-server` に `wrong-host.example.com` という別名も付けてあります。ルートCAを信頼済みでも、証明書の SAN に記載されていないホスト名でアクセスするとどうなるか確認してみましょう。

```bash
docker compose exec client curl -v https://wrong-host.example.com:8443
```

`SSL: no alternative certificate subject name matches target host name 'wrong-host.example.com'` のように拒否されます。**「信頼されたCAの署名」と「SANのホスト名一致」の両方が揃って初めて検証が通る**ことが確認できます。

---

## 2. コンテナ内ブラウザ（noVNC Firefox）での警告なしアクセス体験

Linux のブラウザは OS の `/etc/ssl/certs` とは別の証明書データベース（NSS DB）を参照するため、ブラウザ側にも `ca.crt` を登録して挙動を確認します。

### 2.1 ホストのブラウザからコンテナ内 Firefox を開く

お使いのPCのブラウザで以下の URL を開いてください（`127.0.0.1:5800` のみにバインドされています）。

```text
http://localhost:5800
```

画面内に隔離された Firefox が表示され、自動的に `https://dev.ai-nexus.test:8443` を開きます。

### 2.2 登録前：警告画面が出ることを確認

コンテナ内 Firefox にはまだ `ca.crt` を登録していないため、**「警告: 潜在的なセキュリティリスクあり（MOZILLA_PKIX_ERROR_SELF_SIGNED_CERT 等）」** の警告画面が表示されます。

### 2.3 コンテナ内 Firefox に `ca.crt` をインポート

noVNC 画面上の Firefox 内で以下の操作を行います。

1. Firefox 右上のメニュー（≡）＞ **Settings（設定）** を開く
2. 左メニューの **Privacy & Security（プライバシーとセキュリティ）** を開く
3. 下部にある **Certificates（証明書）** セクションの **View Certificates...（証明書を表示）** をクリック
4. **Authorities（認証局証明書）** タブを開き、**Import...（インポート）** をクリック
5. ファイル選択ダイアログで左ペインの `Computer`（`/`）＞ `certs` ＞ **`ca.crt`** を選択して開く
6. **「Trust this CA to identify websites（この認証局によるウェブサイトの識別を信頼する）」** にチェックを入れて **OK** を押す
   - （このとき、Authorities 一覧に **`AI Nexus (DEV)` → `AI Nexus DEV Root CA`** として登録されたことも確認できます！）

### 2.4 警告なしで表示されることを確認

元のタブ（`https://dev.ai-nexus.test:8443`）に戻って再読み込み（F5 / 更新ボタン）します。

- 警告画面が消え、`index.html`（`HTTPS Self-Signed / Private CA Test Success!`）がそのまま表示されます。
- アドレスバーの **鍵アイコン** をクリックして証明書の詳細を開くと、`AI Nexus DEV Root CA` によって発行された `dev.ai-nexus.test` の証明書として正規に検証されていることを確認できます。

---

## 3. 検証終了後のクリーンアップ（Docker 環境の破棄）

検証が終わったら、以下のコマンド 1 つでサーバー・クライアント・ブラウザのすべてを停止＆削除できます。コンテナ内に登録した `ca.crt` も一緒に完全に消去されます。

```bash
docker compose down
```

（※ ダウンロードした Docker イメージも消したい場合は `docker compose down --rmi all` を実行してください。）

---

## （参考）もしホストPCに直接登録していた場合のクリーンアップ手順

Docker ではなくホストの Ubuntu やブラウザへ直接登録する手順を試していた場合は、以下のコマンドでホスト側から安全に削除できます。

```bash
# Ubuntu システムの信頼ストアから削除
sudo rm -f /usr/local/share/ca-certificates/ai-nexus-dev-ca.crt /usr/local/share/ca-certificates/my-private-ca.crt
sudo update-ca-certificates --fresh

# Chrome / Chromium / Edge の NSS DB (~/.pki/nssdb) から削除（登録していた場合）
certutil -d sql:"$HOME/.pki/nssdb" -D -n "AI Nexus DEV Root CA"
```

---

[← Step 4: プライベートCAとSAN証明書](04_private_ca.md) | [次へ: Step 6 mkcertによる開発環境自動化（参考） →](06_mkcert.md)
