# PR #44「Rails: Google IDトークン認証用の内部セッションAPIを追加」
#
# PR本文に書かれた「非エンジニア向けユーザーテスト手順」（curlでの動作確認）を、
# サーバー起動なしで再現できるRailsのrequest specとして自動化したもの。
# 対象は開発サーバー相当（Rails test環境）のみ。本番サーバーへは一切接続しない。
#
# 対応する手順:
#   手順1: 開発サーバーを起動する
#          -> 自動テストの対象外（本テストはRailsのrequest specとして同等のHTTPリクエストを
#             in-processで発行するため、実サーバー起動は不要）
#   手順2: 別のターミナルを開き、正しい合言葉でAPIを呼び出す（開発用近道の確認）
#          -> "手順2" セクション（200 OK・google_sub=development-user・個人情報が
#             レスポンスに含まれないことを検証）
#   手順3: 間違った合言葉でAPIを呼び出す（拒否されることの確認）
#          -> "手順3" セクション（403 Forbidden・ユーザー未作成を検証）
#   手順4: 合言葉ヘッダーを付けずにAPIを呼び出す
#          -> "手順4" セクション（403 Forbiddenを検証）
#   手順5: サーバーを止める
#          -> 自動テストの対象外
#
# 併せて以下を確認する:
#   - CLAUDE.md必須要件: 個人情報（氏名・メール等）を一切保持せず、opaqueなgoogle_subの
#     みを保持すること（レスポンス・DBの両方を「保存されるカラム／値」として肯定的に確認する）
#   - OWASP A07 (Identification and Authentication Failures): 合言葉なし・不一致での
#     認証バイパスがないこと。development用の近道が非development環境では無効であること
#   - OWASP A02 (Cryptographic Failures): 合言葉比較にタイミング攻撃耐性のある
#     ActiveSupport::SecurityUtils.secure_compare が使われていること
#   - QC10 エラーハンドリング: 想定外の例外（Google検証エラー等）でスタックトレースや
#     生の例外情報を利用者に漏らさず、適切なHTTPステータスのみを返すこと
#
# 実行方法（開発/テストDBのみを対象。config/database.yml の test 環境は sqlite3 の
# storage/test.sqlite3 を使用する。本番サーバーへは一切接続しない）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec spec ../../test/pr44

require "rails_helper"

RSpec.describe "PR44: Google IDトークン認証用の内部セッションAPI (POST /api/v1/session)", type: :request do
  let(:internal_api_secret) { "test-secret-12345" }
  let(:google_client_id) { "google-client-id-pr44" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    allow(ENV).to receive(:fetch).with("GOOGLE_CLIENT_ID").and_return(google_client_id)
  end

  # ---------------------------------------------------------------------
  # 手順2: 正しい合言葉でAPIを呼び出す（開発用近道 development bypass）
  # ---------------------------------------------------------------------
  describe "手順2: 正しい合言葉での呼び出し（development近道）" do
    it "development環境では200 OKとなり、development-userとしてセッションが発行され、個人情報は一切含まれない" do
      allow(Rails.env).to receive(:development?).and_return(true)

      expect {
        post "/api/v1/session", headers: { "X-Internal-API-Secret" => internal_api_secret }
      }.to change(User, :count).by(1)

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body["user"]["google_sub"]).to eq("development-user")
      expect(body["session_token"]).to be_present

      # PR本文どおり: レスポンスにはid/google_subのみが含まれ、メール・氏名等は一切含まれない
      expect(body["user"].keys.sort).to eq(%w[google_sub id])
      expect(response.body).not_to match(/@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/), "メールアドレスらしき文字列が含まれています"
      expect(response.body.downcase).not_to include("email")
      expect(response.body.downcase).not_to include("\"name\"")

      # DB側も肯定的に確認: 実際に保存されたUserレコードのカラムがgoogle_sub/id/created_at/updated_atのみであること
      user = User.find_by!(google_sub: "development-user")
      expect(user.attributes.keys.sort).to eq(%w[created_at google_sub id updated_at])
      expect(user.google_sub).to eq("development-user")
    end

    it "同じ開発用近道を2回呼び出しても、ユーザーが重複作成されず同一レコードに解決される（find_or_create_by!）" do
      allow(Rails.env).to receive(:development?).and_return(true)

      post "/api/v1/session", headers: { "X-Internal-API-Secret" => internal_api_secret }
      first_id = JSON.parse(response.body)["user"]["id"]

      expect {
        post "/api/v1/session", headers: { "X-Internal-API-Secret" => internal_api_secret }
      }.not_to change(User, :count)

      expect(JSON.parse(response.body)["user"]["id"]).to eq(first_id)
    end
  end

  # ---------------------------------------------------------------------
  # 手順3: 間違った合言葉でAPIを呼び出す（拒否されることの確認）
  # ---------------------------------------------------------------------
  describe "手順3: 間違った合言葉での呼び出し" do
    it "403 Forbiddenで拒否され、Googleの検証は一切呼ばれず、ユーザーも作成されない（OWASP A07）" do
      expect(Google::Auth::IDTokens).not_to receive(:verify_oidc)

      expect {
        post "/api/v1/session", headers: { "X-Internal-API-Secret" => "wrong-secret" }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to be_blank
    end
  end

  # ---------------------------------------------------------------------
  # 手順4: 合言葉ヘッダーを付けずにAPIを呼び出す
  # ---------------------------------------------------------------------
  describe "手順4: 合言葉ヘッダーなしでの呼び出し" do
    it "403 Forbiddenで拒否される" do
      expect(Google::Auth::IDTokens).not_to receive(:verify_oidc)

      post "/api/v1/session"

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to be_blank
    end

    it "重大確認: サーバー側でINTERNAL_API_SECRETが未設定(空)の場合、空ヘッダーでも200にならない（OWASP A07: 認証バイパス防止）" do
      allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(nil)

      post "/api/v1/session", headers: { "X-Internal-API-Secret" => "" }

      expect(response).to have_http_status(:forbidden)
    end
  end

  # ---------------------------------------------------------------------
  # PR本文の補足: 実際のGoogle IDトークン検証（development以外の環境）
  # ---------------------------------------------------------------------
  describe "非development環境でのGoogle IDトークン検証" do
    it "正しいIDトークンであれば200 OKとなり、google_subだけでユーザーが特定され、メール・氏名は保存もレスポンスもされない" do
      google_sub = "google-sub-pr44-real"

      allow(Google::Auth::IDTokens).to receive(:verify_oidc)
        .with("valid-token", aud: google_client_id)
        .and_return({ "sub" => google_sub, "email" => "person@example.com", "name" => "PR44 Tester" })

      post "/api/v1/session",
        params: { id_token: "valid-token" },
        headers: { "X-Internal-API-Secret" => internal_api_secret }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["user"]["google_sub"]).to eq(google_sub)
      expect(response.body).not_to include("person@example.com")
      expect(response.body).not_to include("PR44 Tester")

      user = User.find_by!(google_sub: google_sub)
      expect(user.attributes.keys.sort).to eq(%w[created_at google_sub id updated_at])
    end

    it "不正なIDトークンの場合は401で拒否され、ユーザーは作成されない" do
      allow(Google::Auth::IDTokens).to receive(:verify_oidc)
        .and_raise(Google::Auth::IDTokens::VerificationError, "invalid token")

      expect {
        post "/api/v1/session",
          params: { id_token: "invalid-token" },
          headers: { "X-Internal-API-Secret" => internal_api_secret }
      }.not_to change(User, :count)

      expect(response).to have_http_status(:unauthorized)
    end

    it "id_tokenが未指定の場合も401で拒否される（development以外）" do
      post "/api/v1/session", headers: { "X-Internal-API-Secret" => internal_api_secret }

      expect(response).to have_http_status(:unauthorized)
      expect(User.find_by(google_sub: "development-user")).to be_nil
    end

    it "development近道（development-user）は非development環境では成立しない（OWASP A07）" do
      post "/api/v1/session",
        params: { id_token: "" },
        headers: { "X-Internal-API-Secret" => internal_api_secret }

      expect(response).to have_http_status(:unauthorized)
      expect(User.find_by(google_sub: "development-user")).to be_nil
    end
  end

  # ---------------------------------------------------------------------
  # CLAUDE.md必須要件: 個人情報の非保持（DBスキーマレベルの確認）
  # ---------------------------------------------------------------------
  describe "個人情報の非保持（usersテーブルのスキーマ確認）" do
    it "usersテーブルにメール・氏名等の個人情報カラムが一切存在しない" do
      forbidden_columns = %w[
        email name first_name last_name given_name family_name
        avatar_url picture phone_number address birthday
      ]
      expect(User.column_names & forbidden_columns).to eq([])
      expect(User.column_names.sort).to eq(%w[created_at google_sub id updated_at])
    end
  end

  # ---------------------------------------------------------------------
  # OWASP A02: 合言葉比較の実装（タイミング攻撃対策）
  # ---------------------------------------------------------------------
  describe "合言葉比較の実装確認" do
    it "秘密情報の比較にActiveSupport::SecurityUtils.secure_compareが使用されている" do
      source = File.read(Rails.root.join("app/controllers/api/v1/sessions_controller.rb"))
      expect(source).to include("ActiveSupport::SecurityUtils.secure_compare")
    end
  end

  # ---------------------------------------------------------------------
  # QC10 エラーハンドリング: 想定外の例外を隠さず、適切なステータスのみを返す
  # ---------------------------------------------------------------------
  describe "QC10 エラーハンドリング" do
    it "Google検証で例外が発生しても、生の例外クラス名やファイルパスをレスポンス本文に漏らさない" do
      allow(Google::Auth::IDTokens).to receive(:verify_oidc)
        .and_raise(Google::Auth::IDTokens::VerificationError, "invalid token")

      post "/api/v1/session",
        params: { id_token: "invalid-token" },
        headers: { "X-Internal-API-Secret" => internal_api_secret }

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include("VerificationError")
      expect(response.body).not_to include("sessions_controller.rb")
    end
  end
end
