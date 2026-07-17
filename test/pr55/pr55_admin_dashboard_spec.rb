# PR #55「管理画面のBASIC認証と契約・支払一覧をRailsで実装」
#
# PR本文に書かれた「非エンジニア向けユーザーテスト手順」を自動再現するテスト（バックエンド部分）。
# 対象は開発環境の Rails アプリケーション（config/database.yml の test 環境 = storage/test.sqlite3、
# 開発サーバーの development 環境と同じ SQLite）であり、本番サーバー・本番DB（PostgreSQL）へは
# 一切接続しない。BASIC認証情報（ADMIN_BASIC_USER / ADMIN_BASIC_PASSWORD）はテスト内で
# 開発環境の初期値（admin / changeme、PR本文記載の値）をスタブして使用する。
#
# 対応する手順（PR本文より）:
#   手順1: 管理画面にログインする
#          -> "手順1" セクション（BASIC認証ダイアログ相当の401/WWW-Authenticate、
#             誤ったユーザー名・パスワードでの再拒否、正しい認証情報でのログイン成功を検証）
#   手順2: 契約一覧を確認する
#          -> "手順2" セクション（/admin の表ヘッダ列・実データ表示を検証）
#   手順3: 支払一覧を確認する
#          -> "手順3" セクション（/admin/payouts の表ヘッダ列・「指図済」行のみボタン表示、
#             それ以外の行は「操作済み」表示でボタンなしを検証）
#   手順4: 支払を「完了（模擬）」にする操作を試す
#          -> "手順4" セクション（支払完了操作で状態が変わり画面に戻ること、
#             二重操作でボタンが表示されなくなることを検証）
#   手順5: 支払を「無効化」する操作を試す
#          -> "手順5" セクション（無効化操作、完了済み支払は無効化できないことを検証）
#   手順6: ログイン情報なしでのアクセス確認（任意・セキュリティ確認）
#          -> "手順6" セクション（認証なしでは契約・支払の中身が一切表示されないことを検証）
#
# 併せて QC10（エラーハンドリング）・OWASP10（特に A01 Broken Access Control、
# A02 Cryptographic Failures、A05 Security Misconfiguration、A07 Identification and
# Authentication Failures、A08 Software and Data Integrity Failures）の該当観点を確認する。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr55/pr55_admin_dashboard_spec.rb

require "rails_helper"

RSpec.describe "PR55: 管理画面のBASIC認証と契約・支払一覧", type: :request do
  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme" }
  let(:valid_auth_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}" }
  end
  let(:wrong_password_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:totally-wrong-password")}" }
  end
  let(:wrong_user_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("not-admin:#{admin_password}")}" }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)

    # 契約状態マスタ（6件）・支払状態マスタ（3件）を設計資料1.7のとおり用意する。
    # Payoutモデルのafter_saveコールバック（支払確定時の契約状態遷移）が
    # PolicyStatus.find_by!(code: "active"/"cap_reached"/"expired") 等を参照するため、
    # 最小単位のマスタデータであっても全件そろえておく必要がある
    find_or_create_policy_status("waiting", 0, "待機中")
    find_or_create_policy_status("active", 1, "有効")
    find_or_create_policy_status("processing", 2, "支払処理中")
    find_or_create_policy_status("cap_reached", 3, "上限到達")
    find_or_create_policy_status("cancelled", 4, "解約")
    find_or_create_policy_status("expired", 5, "失効")
    find_or_create_payout_status("ordered", 0, "指図済")
    find_or_create_payout_status("completed_simulated", 1, "支払完了（模擬）")
    find_or_create_payout_status("invalid", 2, "無効")
  end

  # ---------------------------------------------------------------------
  # 手順1: 管理画面にログインする
  # ---------------------------------------------------------------------
  describe "手順1: 管理画面へのログイン（BASIC認証）" do
    it "認証情報なしで /admin を開くとブラウザの認証ダイアログ相当の401とWWW-Authenticateヘッダが返る" do
      get "/admin"

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to match(/Basic/i)
    end

    it "失敗パターン: 誤ったパスワードでは再度401（同じ入力ダイアログが繰り返される相当）" do
      get "/admin", headers: wrong_password_headers

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include("契約一覧")
    end

    it "失敗パターン: 誤ったユーザー名では再度401" do
      get "/admin", headers: wrong_user_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "正しいユーザー名・パスワードでログインすると「保険（デモ）管理画面」画面に切り替わる" do
      get "/admin", headers: valid_auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("保険（デモ）管理画面")
      expect(response.body).to include("模擬支払の運用確認用画面です")
      expect(response.body).to include("契約一覧")
      expect(response.body).to include("支払一覧")
    end
  end

  # ---------------------------------------------------------------------
  # 手順2: 契約一覧を確認する
  # ---------------------------------------------------------------------
  describe "手順2: 契約一覧（/admin）" do
    it "表形式で規定の列が表示され、実データが正しく反映される" do
      user = User.create!(google_sub: "google-sub-pr55-policy")
      plan = find_or_create_plan("seismic_pr55_policy")
      station = find_or_create_station("seismic_tokyo_pr55_policy")
      payout_tier = find_or_create_payout_tier("ten_thousand_pr55_policy")
      processing_status = find_or_create_policy_status("processing", 2, "支払処理中")

      policy = Policy.create!(
        user: user, plan: plan, station: station, payout_tier: payout_tier,
        policy_status: processing_status, threshold: "5強"
      )
      policy.update_columns(
        waiting_until: 1.day.ago,
        expires_at: 1.year.from_now
      )

      get "/admin", headers: valid_auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("契約一覧")

      %w[ユーザー プラン 観測点 閾値 状態 年間支払回数 免責明け時刻].each do |column|
        expect(response.body).to include(column), "列見出し「#{column}」が表示されていません"
      end

      # 一覧の内容が実データ（PR本文の列と対応）と一致すること
      expect(response.body).to include(user.google_sub)
      expect(response.body).to include(plan.code)
      expect(response.body).to include(station.code)
      expect(response.body).to include("5強")
      expect(response.body).to include(processing_status.code)
      expect(response.body).to include(policy.reload.waiting_until.strftime("%Y-%m-%d %H:%M"))
    end

    it "失敗パターン: データが1件もなくても500やエラー画面にならず200で表が空表示される" do
      get "/admin", headers: valid_auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("契約一覧")
      expect(response.body).not_to include("500")
      expect(response.body).not_to include("エラーが発生しました")
    end
  end

  # ---------------------------------------------------------------------
  # 手順3: 支払一覧を確認する
  # ---------------------------------------------------------------------
  describe "手順3: 支払一覧（/admin/payouts）" do
    it "規定の列が表示され、「指図済」の行にのみ2つの操作ボタンが表示される" do
      user = User.create!(google_sub: "google-sub-pr55-payout-list")
      ordered_payout = build_ordered_payout_for(user, suffix: "list-ordered")
      completed_payout = build_completed_payout_for(user, suffix: "list-completed")
      invalid_payout = build_invalid_payout_for(user, suffix: "list-invalid")

      get "/admin/payouts", headers: valid_auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("支払一覧")

      %w[ID ユーザー プラン 観測点 閾値 状態 判定時刻 操作].each do |column|
        expect(response.body).to include(column), "列見出し「#{column}」が表示されていません"
      end

      doc = Nokogiri::HTML.parse(response.body)
      rows = doc.css("table tbody tr")

      ordered_row = find_row_by_id(rows, ordered_payout.id)
      completed_row = find_row_by_id(rows, completed_payout.id)
      invalid_row = find_row_by_id(rows, invalid_payout.id)

      expect(ordered_row.css("td")[5].text.strip).to eq("ordered")
      expect(ordered_row.css("button").map(&:text)).to contain_exactly("支払完了（模擬）にする", "無効化")
      expect(ordered_row.text).not_to include("操作済み")

      expect(completed_row.css("td")[5].text.strip).to eq("completed_simulated")
      expect(completed_row.css("button")).to be_empty
      expect(completed_row.text).to include("操作済み")

      expect(invalid_row.css("td")[5].text.strip).to eq("invalid")
      expect(invalid_row.css("button")).to be_empty
      expect(invalid_row.text).to include("操作済み")
    end

    it "失敗パターン: ボタンが「指図済」以外の行に出てしまっていない、または全行に出てしまっていない" do
      user = User.create!(google_sub: "google-sub-pr55-payout-buttons")
      build_completed_payout_for(user, suffix: "buttons-only-completed")

      get "/admin/payouts", headers: valid_auth_headers

      doc = Nokogiri::HTML.parse(response.body)
      # 「指図済」行が存在しない場合、ボタンは1つも表示されないはず
      expect(doc.css("table tbody tr button")).to be_empty
    end
  end

  # ---------------------------------------------------------------------
  # 手順4: 支払を「完了（模擬）」にする操作を試す
  # ---------------------------------------------------------------------
  describe "手順4: 支払完了（模擬）操作" do
    it "「支払完了（模擬）にする」ボタン相当のリクエストで状態が変わり、支払一覧画面に戻る" do
      user = User.create!(google_sub: "google-sub-pr55-complete")
      payout = build_ordered_payout_for(user, suffix: "complete-flow")

      patch "/admin/api/payouts/#{payout.id}/complete",
        headers: valid_auth_headers,
        params: { return_to_admin_payouts: "1" }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("/admin/payouts")

      # follow_redirect! はBASIC認証ヘッダーを引き継がないため、実際のブラウザの
      # 「ボタンを押すと画面遷移する」挙動に合わせて改めて認証付きで遷移先を取得する
      get response.headers["Location"], headers: valid_auth_headers
      expect(response).to have_http_status(:ok)

      doc = Nokogiri::HTML.parse(response.body)
      row = find_row_by_id(doc.css("table tbody tr"), payout.id)
      expect(row.css("td")[5].text.strip).to eq("completed_simulated")
      expect(row.text).to include("操作済み")
      expect(row.css("button")).to be_empty
    end

    it "二重操作防止: 一度「完了（模擬）」になった行にはもう一度操作するボタン自体が表示されない" do
      user = User.create!(google_sub: "google-sub-pr55-complete-twice")
      payout = build_ordered_payout_for(user, suffix: "complete-twice")

      patch "/admin/api/payouts/#{payout.id}/complete", headers: valid_auth_headers

      get "/admin/payouts", headers: valid_auth_headers
      doc = Nokogiri::HTML.parse(response.body)
      row = find_row_by_id(doc.css("table tbody tr"), payout.id)
      expect(row.css("button")).to be_empty
    end

    it "失敗パターン: 存在しない支払IDを操作しようとしても生の500エラーにならず404で処理される（QC10エラーハンドリング）" do
      patch "/admin/api/payouts/999999999/complete", headers: valid_auth_headers

      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------
  # 手順5: 支払を「無効化」する操作を試す
  # ---------------------------------------------------------------------
  describe "手順5: 支払の無効化操作" do
    it "「指図済」の支払を無効化すると状態が「無効」になる" do
      user = User.create!(google_sub: "google-sub-pr55-invalidate")
      payout = build_ordered_payout_for(user, suffix: "invalidate-flow")

      patch "/admin/api/payouts/#{payout.id}/invalidate",
        headers: valid_auth_headers,
        params: { return_to_admin_payouts: "1" }

      expect(response).to have_http_status(:see_other)
      get response.headers["Location"], headers: valid_auth_headers

      doc = Nokogiri::HTML.parse(response.body)
      row = find_row_by_id(doc.css("table tbody tr"), payout.id)
      expect(row.css("td")[5].text.strip).to eq("invalid")
      expect(row.text).to include("操作済み")
    end

    it "失敗パターン: すでに「支払完了（模擬）」の支払を無効化しようとすると422で拒否され、状態が変わらない（正しい挙動）" do
      user = User.create!(google_sub: "google-sub-pr55-invalidate-completed")
      payout = build_completed_payout_for(user, suffix: "invalidate-completed")

      patch "/admin/api/payouts/#{payout.id}/invalidate", headers: valid_auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(payout.reload.payout_status.code).to eq("completed_simulated")
    end
  end

  # ---------------------------------------------------------------------
  # 手順6: ログイン情報なしでのアクセス確認（セキュリティ確認）
  # ---------------------------------------------------------------------
  describe "手順6: ログイン情報なしでのアクセス確認（OWASP A01 / A07）" do
    it "認証なしで /admin にアクセスしても契約データの中身は一切表示されない" do
      user = User.create!(google_sub: "google-sub-pr55-secret-leak")
      plan = find_or_create_plan("seismic_pr55_secret_leak")
      station = find_or_create_station("seismic_tokyo_pr55_secret_leak")
      payout_tier = find_or_create_payout_tier("ten_thousand_pr55_secret_leak")
      active_status = find_or_create_policy_status("active", 1, "有効")
      Policy.create!(
        user: user, plan: plan, station: station, payout_tier: payout_tier,
        policy_status: active_status, threshold: "5強"
      )

      get "/admin"

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include(user.google_sub)
      expect(response.body).not_to include(plan.code)
      expect(response.body).not_to include("契約一覧")
    end

    it "認証なしで /admin/payouts にアクセスしても支払データの中身は一切表示されない" do
      user = User.create!(google_sub: "google-sub-pr55-secret-leak-payouts")
      payout = build_ordered_payout_for(user, suffix: "secret-leak-payouts")

      get "/admin/payouts"

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).not_to include(user.google_sub)
      expect(response.body).not_to include(payout.id.to_s)
      expect(response.body).not_to include("支払一覧")
    end

    it "認証なしでは支払完了・無効化のAPIも実行できない（状態は変化しない）" do
      user = User.create!(google_sub: "google-sub-pr55-secret-leak-api")
      payout = build_ordered_payout_for(user, suffix: "secret-leak-api")

      patch "/admin/api/payouts/#{payout.id}/complete"
      expect(response).to have_http_status(:unauthorized)

      patch "/admin/api/payouts/#{payout.id}/invalidate"
      expect(response).to have_http_status(:unauthorized)

      expect(payout.reload.payout_status.code).to eq("ordered")
    end
  end

  # ---------------------------------------------------------------------
  # QC10 / OWASP10 追加観点
  # ---------------------------------------------------------------------
  describe "QC10・OWASP10 追加観点" do
    it "OWASP A02: 管理者資格情報が未設定(nil)でも例外にならず安全に401で拒否される（secure_compareのブランク考慮）" do
      allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(nil)
      allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(nil)

      expect { get "/admin", headers: valid_auth_headers }.not_to raise_error
      expect(response).to have_http_status(:unauthorized)
    end

    it "OWASP A05: 管理画面のセッションCookieは /admin 配下に限定され、SameSite=Strictである" do
      orig = ActionController::Base.allow_forgery_protection
      begin
        ActionController::Base.allow_forgery_protection = true
        # 支払一覧に「指図済」の行（＝CSRFトークン付きフォーム）が最低1件ないと
        # セッションが書き込まれずSet-Cookieが発行されないため、フィクスチャを用意する
        user = User.create!(google_sub: "google-sub-pr55-cookie-scope")
        build_ordered_payout_for(user, suffix: "cookie-scope")

        get "/admin/payouts", headers: valid_auth_headers

        set_cookie = response.headers["Set-Cookie"]
        expect(set_cookie).to include("_backend_admin_session=")
        expect(set_cookie).to include("path=/admin")
        expect(set_cookie).to include("samesite=strict")
      ensure
        ActionController::Base.allow_forgery_protection = orig
      end
    end

    it "OWASP A08: CSRFトークンなしでの支払完了・無効化リクエストは422で拒否される" do
      orig_base = ActionController::Base.allow_forgery_protection
      orig_api = Admin::Api::PayoutsController.allow_forgery_protection
      begin
        ActionController::Base.allow_forgery_protection = true
        Admin::Api::PayoutsController.allow_forgery_protection = true

        user = User.create!(google_sub: "google-sub-pr55-csrf")
        payout = build_ordered_payout_for(user, suffix: "csrf")

        patch "/admin/api/payouts/#{payout.id}/complete", headers: valid_auth_headers
        expect(response).to have_http_status(:unprocessable_entity)
        expect(payout.reload.payout_status.code).to eq("ordered")
      ensure
        ActionController::Base.allow_forgery_protection = orig_base
        Admin::Api::PayoutsController.allow_forgery_protection = orig_api
      end
    end

    it "OWASP A08: 無効化処理中に別操作で先に支払完了となった場合、行ロックにより上書きされない（競合対策）" do
      user = User.create!(google_sub: "google-sub-pr55-race")
      payout = build_ordered_payout_for(user, suffix: "race")
      completed_status = find_or_create_payout_status("completed_simulated", 1, "支払完了（模擬）")

      already_updated = false
      allow_any_instance_of(Payout).to receive(:reload).and_wrap_original do |original_method, *args|
        unless already_updated
          already_updated = true
          Payout.where(id: payout.id).update_all(payout_status_id: completed_status.id)
        end
        original_method.call(*args)
      end

      patch "/admin/api/payouts/#{payout.id}/invalidate", headers: valid_auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(payout.reload.payout_status.code).to eq("completed_simulated")
    end

    it "QC10: 不正な状態遷移エラーはRailsの生スタックトレースではなく整形されたエラーメッセージを返す" do
      user = User.create!(google_sub: "google-sub-pr55-error-message")
      payout = build_completed_payout_for(user, suffix: "error-message")

      patch "/admin/api/payouts/#{payout.id}/invalidate", headers: valid_auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("無効な状態遷移です")
      expect(response.body).not_to include("app/controllers")
      expect(response.body).not_to include("ActiveRecord::")
    end
  end

  # =======================================================================
  # フィクスチャ生成ヘルパー
  # =======================================================================

  def find_row_by_id(rows, id)
    row = rows.find { |r| r.css("td")[0]&.text&.strip == id.to_s }
    raise "ID=#{id} の行が見つかりません" unless row

    row
  end

  def build_ordered_payout_for(user, suffix:)
    build_payout_for(user, suffix: suffix, payout_status_code: "ordered")
  end

  def build_completed_payout_for(user, suffix:)
    build_payout_for(user, suffix: suffix, payout_status_code: "completed_simulated")
  end

  def build_invalid_payout_for(user, suffix:)
    build_payout_for(user, suffix: suffix, payout_status_code: "invalid")
  end

  def build_payout_for(user, suffix:, payout_status_code:)
    plan = find_or_create_plan("seismic_pr55_#{suffix}")
    station = find_or_create_station("seismic_tokyo_pr55_#{suffix}")
    payout_tier = find_or_create_payout_tier("ten_thousand_pr55_#{suffix}")
    processing_status = PolicyStatus.find_by!(code: "processing")
    payout_status = PayoutStatus.find_by!(code: payout_status_code)
    level = shared_seismic_level

    policy = Policy.create!(
      user: user, plan: plan, station: station, payout_tier: payout_tier,
      policy_status: processing_status, threshold: "5強"
    )
    policy.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now)

    observation = Observation.create!(
      station: station, event_id: "event-pr55-#{suffix}", observed_at: Time.current,
      seismic_intensity_level: level, max_value: level.sort_order, simulated: true
    )

    Payout.create!(
      policy: policy, payout_tier: payout_tier, payout_status: payout_status, observation: observation,
      idempotency_key: "policy_pr55_#{suffix}", decided_at: Time.current
    )
  end

  # 震度階級マスタは1レコード共有すれば十分なため、テスト全体で使い回す
  # （SeismicIntensityLevel.sort_orderの一意制約に抵触しないようにするため）
  def shared_seismic_level
    find_or_create_level("pr55_shared_seismic_level", 6)
  end

  def find_or_create_plan(code)
    Plan.find_or_create_by!(code: code) do |p|
      p.trigger_type = "seismic"
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| p.public_send("#{attr}=", "震度連動") }
    end
  end

  def find_or_create_station(code)
    Station.find_or_create_by!(code: code) do |s|
      s.measurement_type = "seismic"
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| s.public_send("#{attr}=", "東京震度観測点") }
    end
  end

  def find_or_create_payout_tier(code)
    PayoutTier.find_or_create_by!(code: code) do |t|
      t.amount_yen = 10_000
      %i[label_ja label_en label_fr label_zh label_ru label_es label_ar].each { |attr| t.public_send("#{attr}=", "1万円相当（模擬）") }
    end
  end

  # sort_order はDB全体で一意制約があるため、決め打ちの値ではなく現在の最大値+1を
  # 採番する。他specやシード投入済みの既存マスタと衝突しないようにするため
  def next_sort_order(klass)
    (klass.maximum(:sort_order) || -1) + 1
  end

  def find_or_create_policy_status(code, _sort_order = nil, label_ja)
    PolicyStatus.find_by(code: code) || PolicyStatus.create!(
      code: code, sort_order: next_sort_order(PolicyStatus),
      **%i[label_ja label_en label_fr label_zh label_ru label_es label_ar].index_with { label_ja }
    )
  end

  def find_or_create_payout_status(code, _sort_order = nil, label_ja)
    PayoutStatus.find_by(code: code) || PayoutStatus.create!(
      code: code, sort_order: next_sort_order(PayoutStatus),
      **%i[label_ja label_en label_fr label_zh label_ru label_es label_ar].index_with { label_ja }
    )
  end

  def find_or_create_level(code, _sort_order = nil)
    SeismicIntensityLevel.find_by(code: code) || SeismicIntensityLevel.create!(
      code: code, sort_order: next_sort_order(SeismicIntensityLevel),
      **%i[label_ja label_en label_fr label_zh label_ru label_es label_ar].index_with { "5強" }
    )
  end
end
