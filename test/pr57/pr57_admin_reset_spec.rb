# PR#57「管理画面にデモデータ初期化用のリセットタブを追加」用の自動テスト。
#
# 対象: https://github.com/<org>/parametric-disaster-payout-mvp/pull/57
# 本テストは PR#57 の本文に書かれた「非エンジニア向けユーザーテスト手順」を
# RSpec の request spec として再現する（ブラックボックステスト、Rails の
# test 環境=開発用DBを使用。production／本番サーバーには一切接続しない）。
#
# PR本文の手順との対応:
#   前提条件                 -> "前提条件" セクション（BASIC認証情報の確認）
#   手順1（管理画面ログイン） -> describe "手順1"
#   手順2（リセット画面を開く）-> describe "手順2"
#   手順3（確認文字列なしで実行→失敗）-> describe "手順3"
#   手順4（正しい確認文字列で実行→成功）-> describe "手順4"
#   手順5（他タブでデータが消えていることを確認）-> describe "手順5"
#   テスト後の後片付けについて -> 本テストは専用の test DB（storage/test.sqlite3）
#                                のみを対象にしており、開発DB・本番DBには一切
#                                書き込まない（rails_helper が use_transactional_fixtures
#                                でテスト用トランザクション内に閉じ込める）。
#
# 併せて QC10 / OWASP10 の該当観点も確認する（末尾の describe を参照）。
#
# 実行方法:
#   cd src/backend
#   bundle exec rspec ../../test/pr57/pr57_admin_reset_spec.rb
#
# 実行結果は事前に確認済み（Issue #63対応後は 21 examples, 0 failures, 0 pending。
# OWASP A08(CSRF)の既知の指摘は本ファイル末尾のdescribeで対応済みとして検証している）。
#
# 補足: 本ファイルとは別に、実際に `bin/rails server` を起動して本物のHTTPで
# 検証する test/pr57/pr57_reset_tab.e2e.spec.js（Playwright）も用意している。
# そちらでは、RSpecのrequest specだけでは検出できない実サーバー特有の不具合
# （config.api_only=trueによるActionDispatch::Flashミドルウェア欠落）を検出した。
# 詳細はそのファイルの冒頭コメントを参照。
#
# 注意（重要）: 上記のPlaywright側は別プロセスの `bin/rails server -e test` を
# 起動し、storage/test.sqlite3 に対して（RSpecのトランザクションによる
# ロールバックが効かない形で）直接データを書き込む。そのため、Playwright側を
# 実行した直後にこのRSpecを実行すると、本テストが前提とするレコード件数
# （例: Policies 1件）が食い違い失敗することがある。両方を実行する場合は、
# 先に `RAILS_ENV=test bundle exec rails db:test:prepare` で
# storage/test.sqlite3 をまっさらな状態に戻してから本ファイルを実行すること。

require "rails_helper"

RSpec.describe "PR#57 管理画面リセットタブ（デモデータ初期化）", type: :request do
  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme" }
  let(:auth_headers) do
    {
      "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}"
    }
  end
  let(:wrong_auth_headers) do
    {
      "Authorization" => "Basic #{Base64.strict_encode64("attacker:wrong-password")}"
    }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)
    # マスタデータ26件（保険プラン・震度階級・観測点・支払額区分・契約状態・支払状態）を投入する。
    load Rails.root.join("db/seeds.rb")
  end

  # --- 前提条件：契約一覧・支払一覧に事前データが入っている状態を再現する ---
  let(:user) { User.create!(google_sub: "google-sub-pr57-user") }
  let(:plan) { Plan.find_by!(code: "seismic") }
  let(:station) { Station.find_by!(code: "seismic_tokyo") }
  let(:payout_tier) { PayoutTier.find_by!(code: "ten_thousand") }
  let!(:processing_status) { PolicyStatus.find_by!(code: "processing") }
  let!(:completed_payout_status) { PayoutStatus.find_by!(code: "completed_simulated") }
  let!(:seismic_level) { SeismicIntensityLevel.find_by!(code: "5_strong") }

  let!(:policy) do
    Policy.create!(
      user: user,
      plan: plan,
      station: station,
      payout_tier: payout_tier,
      policy_status: processing_status,
      threshold: "5強"
    ).tap do |record|
      record.update_columns(
        waiting_until: 1.day.ago,
        expires_at: 1.year.from_now
      )
    end
  end

  let!(:observation) do
    Observation.create!(
      station: station,
      event_id: "event-pr57-001",
      observed_at: Time.current,
      seismic_intensity_level: seismic_level,
      max_value: seismic_level.sort_order,
      simulated: true
    )
  end

  let!(:payout) do
    Payout.create!(
      policy: policy,
      payout_tier: payout_tier,
      payout_status: completed_payout_status,
      observation: observation,
      idempotency_key: "policy_#{policy.id}_event_event-pr57-001",
      decided_at: Time.current
    )
  end

  let!(:notification) do
    Notification.create!(
      user: user,
      policy: policy,
      payout: payout,
      kind: Notification::KIND_PAYOUT_ORDERED,
      message: "ordered"
    )
  end

  let!(:survey_response) do
    SurveyResponse.create!(
      user: user,
      payout: payout,
      response_data: { "satisfaction" => 5, "answer" => "yes" }
    )
  end

  let!(:processed_jma_entry) do
    ProcessedJmaEntry.create!(entry_id: "urn:uuid:pr57-entry")
  end

  def transactional_counts
    [
      Policy.count,
      Observation.count,
      Payout.count,
      Notification.count,
      SurveyResponse.count,
      ProcessedJmaEntry.count
    ]
  end

  # ---------------------------------------------------------------------
  # 手順1：管理画面にログインする
  # ---------------------------------------------------------------------
  describe "手順1: 管理画面にBASIC認証でログインする" do
    it "認証情報なしでは401 Unauthorizedになる（期待される失敗パターンの逆＝正しい防御）" do
      get "/admin/reset"

      expect(response).to have_http_status(:unauthorized)
    end

    it "誤ったBASIC認証情報では401になる（OWASP A07: 認証の欠陥対策）" do
      get "/admin/reset", headers: wrong_auth_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "正しい認証情報では契約一覧などのタブが並ぶ管理画面が表示される" do
      get "/admin/reset", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("契約一覧")
      expect(response.body).to include("支払一覧")
      expect(response.body).to include("模擬イベント注入")
      expect(response.body).to include("リセット")
    end
  end

  # ---------------------------------------------------------------------
  # 手順2：リセット画面を開く
  # ---------------------------------------------------------------------
  describe "手順2: リセット画面を開く" do
    it "タイトル・説明文・注意書き・削除予定件数が表示される" do
      get "/admin/reset", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("リセット")
      expect(response.body).to include("デモを繰り返すため、取引データだけを初期化します。")
      expect(response.body).to include("この操作は元に戻せません。")
      expect(response.body).to include("Policies: 1件")
      expect(response.body).to include("Observations: 1件")
      expect(response.body).to include("Payouts: 1件")
      expect(response.body).to include("Notifications: 1件")
      expect(response.body).to include("SurveyResponses: 1件")
      expect(response.body).to include("Users: 1件")
      expect(response.body).to include("マスタ: 26件")
    end

    it "本番環境ではGETでも404になる（失敗パターン：本番では画面自体が開けないのが正しい動作）" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      get "/admin/reset", headers: auth_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------
  # 手順3：確認文字列を入力せずに実行しようとする（失敗するケースの確認）
  # ---------------------------------------------------------------------
  describe "手順3: 確認文字列を入力せずに実行しようとする" do
    it "confirmation_text未送信の場合は失敗メッセージが表示され、データは削除されない" do
      expect do
        post "/admin/reset", headers: auth_headers
      end.not_to change { transactional_counts }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("データ初期化に失敗しました。入力内容をご確認ください。")
    end

    it "確認文字列が1文字でも違う（誤字）場合は失敗し、データは削除されない（一字一句の一致が必須）" do
      expect do
        post "/admin/reset",
          headers: auth_headers,
          params: { confirmation_text: "デモデータを初期化します" } # 「する」ではなく「します」の誤字を模倣
      end.not_to change { transactional_counts }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "空文字列や記号だけの入力でも失敗し、データは削除されない" do
      expect do
        post "/admin/reset", headers: auth_headers, params: { confirmation_text: "" }
      end.not_to change { transactional_counts }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ---------------------------------------------------------------------
  # 手順4：正しい確認文字列を入力して実行する
  # ---------------------------------------------------------------------
  describe "手順4: 正しい確認文字列を入力して実行する" do
    it "対象テーブルが0件になり、成功メッセージが表示される" do
      expect do
        post "/admin/reset",
          headers: auth_headers,
          params: { confirmation_text: ResetDemoData::CONFIRMATION_TEXT }
      end.to change { transactional_counts }.from([ 1, 1, 1, 1, 1, 1 ]).to([ 0, 0, 0, 0, 0, 0 ])

      expect(response).to redirect_to("/admin/reset")

      get "/admin/reset", headers: auth_headers
      expect(response.body).to include("デモデータを初期化しました。")
    end

    it "ユーザー数とマスタ件数（26件）はリセット前後で変わらない" do
      post "/admin/reset",
        headers: auth_headers,
        params: { confirmation_text: ResetDemoData::CONFIRMATION_TEXT }

      expect(User.count).to eq(1)
      expect(
        [ Plan, Station, PayoutTier, PolicyStatus, PayoutStatus, SeismicIntensityLevel ].sum(&:count)
      ).to eq(26)

      get "/admin/reset", headers: auth_headers
      expect(response.body).to include("Users: 1件")
      expect(response.body).to include("マスタ: 26件")
    end
  end

  # ---------------------------------------------------------------------
  # 手順5：他のタブでデータが消えていることを確認する
  # ---------------------------------------------------------------------
  describe "手順5: 他のタブでデータが消えていることを確認する" do
    before do
      post "/admin/reset",
        headers: auth_headers,
        params: { confirmation_text: ResetDemoData::CONFIRMATION_TEXT }
    end

    it "契約一覧タブにテスト用の契約が表示されなくなる" do
      # 契約一覧は管理画面のルート（/admin）にマッピングされている
      get "/admin", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("google-sub-pr57-user")
    end

    it "支払一覧タブにテスト用の支払が表示されなくなる" do
      get "/admin/payouts", headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("google-sub-pr57-user")
    end
  end

  # ---------------------------------------------------------------------
  # QC10（品質管理10項目）関連
  # ---------------------------------------------------------------------
  describe "QC10: エラーハンドリング（404/500ページの整備、適切なエラー表示）" do
    it "QC10: 本番環境アクセス時はクラッシュせず404が返る（index/createの両方）" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

      get "/admin/reset", headers: auth_headers
      expect(response).to have_http_status(:not_found)

      post "/admin/reset",
        headers: auth_headers,
        params: { confirmation_text: ResetDemoData::CONFIRMATION_TEXT }
      expect(response).to have_http_status(:not_found)
      # 本番相当の設定でも実行不可であることの証跡としてデータが残っていることを確認
      expect(Policy.count).to eq(1)
    end

    it "QC10: 確認文字列不一致時は500エラーにならず422+案内メッセージで応答する" do
      post "/admin/reset", headers: auth_headers, params: { confirmation_text: "違う文字列" }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("データ初期化に失敗しました。入力内容をご確認ください。")
    end
  end

  describe "QC07: アクセシビリティ（フォームラベルの関連付け）" do
    it "確認文字列の入力欄にlabel forが正しく紐づいている" do
      get "/admin/reset", headers: auth_headers

      expect(response.body).to match(%r{<label for="confirmation_text">})
      expect(response.body).to match(/id="confirmation_text"/)
    end
  end

  # ---------------------------------------------------------------------
  # OWASP10 関連（破壊的操作＝権限のないユーザーが実行できないことを重点確認）
  # ---------------------------------------------------------------------
  describe "OWASP A01: Broken Access Control / A07: Identification and Authentication Failures" do
    it "認証なしのPOST（リセット実行）は拒否され、データは一切削除されない" do
      expect do
        post "/admin/reset", params: { confirmation_text: ResetDemoData::CONFIRMATION_TEXT }
      end.not_to change { transactional_counts }

      expect(response).to have_http_status(:unauthorized)
    end

    it "誤った認証情報でのPOST（リセット実行）は拒否され、データは一切削除されない" do
      expect do
        post "/admin/reset",
          headers: wrong_auth_headers,
          params: { confirmation_text: ResetDemoData::CONFIRMATION_TEXT }
      end.not_to change { transactional_counts }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "OWASP A04: Insecure Design（誤操作防止の設計）" do
    it "GETリクエスト（画面表示）だけではデータは一切変更されない（安全な副作用なしGET）" do
      expect do
        get "/admin/reset", headers: auth_headers
      end.not_to change { transactional_counts }
    end

    it "確認文字列を渡さない限りリセットは実行できない（単純なワンクリックでは削除されない設計）" do
      expect do
        post "/admin/reset", headers: auth_headers, params: { confirmation_text: nil }
      end.not_to change { transactional_counts }
    end

    it "ビュー・コントローラ・サービスの実装がネイティブのalert()/confirm()/prompt()を使用していない" do
      view_source = Rails.root.join("app/views/admin/reset/index.html.erb").read
      controller_source = Rails.root.join("app/controllers/admin/reset_controller.rb").read
      service_source = Rails.root.join("app/services/reset_demo_data.rb").read

      [ view_source, controller_source, service_source ].each do |source|
        expect(source).not_to match(/\balert\s*\(/)
        expect(source).not_to match(/\bconfirm\s*\(/)
        expect(source).not_to match(/\bprompt\s*\(/)
      end

      # カスタムのモーダル（<dialog>）で実行前確認を行っていることの確認
      expect(view_source).to include("<dialog")
      expect(view_source).to include("showModal()")
    end
  end

  describe "OWASP A08: Software and Data Integrity Failures（CSRF対策）" do
    # Issue #63で対応済み: Admin::HtmlController（Admin::ResetController の親クラス）に
    # protect_from_forgery with: :exception を追加し、CSRFトークン検証
    # （verify_authenticity_token）を有効化した。BASIC認証はブラウザが資格情報を
    # 自動的に再送するため、Cookieに対するSameSite保護の対象外であり、別オリジンの
    # 罠ページから /admin/reset へ自動送信されるCSRF攻撃を受けるリスクがあった
    # （対して Admin::Api::PayoutsController は元々 protect_from_forgery を
    # 呼んでおり対策済みだった）。
    #
    # 注意: test環境は config.action_dispatch.show_exceptions = :rescuable のため、
    # ActionController::InvalidAuthenticityToken はRuby例外として呼び出し元まで
    # 伝播せず、Rackミドルウェアが捕捉して422レスポンスに変換する（本番相当の
    # 挙動）。そのためraise_errorではなくレスポンスステータスで検証する。
    it "本番相当の設定（forgery protection有効時）ではCSRFトークンなしのPOSTが拒否される" do
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true

      begin
        post "/admin/reset",
          headers: auth_headers,
          params: { confirmation_text: ResetDemoData::CONFIRMATION_TEXT }

        expect(response).to have_http_status(:unprocessable_entity)
      ensure
        ActionController::Base.allow_forgery_protection = original
      end

      # CSRF検証で弾かれ、削除処理まで到達していないことを確認
      expect(Policy.count).to eq(1)
    end
  end
end
