# PR #50「F4 支払完了（模擬）とアプリ内通知を追加」
#
# [重要な前提] このPRの本文には、PR #55以降のPRで採用されている
# 「非エンジニア向けユーザーテスト手順」の見出しが存在しない（pr-checkerエージェントの
# 運用がPR #55から始まったため、本PRはその形式ができる前にマージされている）。
# そのため本ファイルは、PR本文に実際に書かれている以下の内容を「非エンジニアが
# curlで追試できる手順」として読み替え、再現するテストとする。
#
#   PR本文より（原文まま）:
#     # 管理者確認で支払完了（模擬）へ
#     PATCH /admin/api/payouts/:id/complete
#     Authorization: Basic base64(admin:password)
#
#     # 生成される通知
#     payout_completed
#     survey_request
#
#   PR本文の説明文（原文まま）:
#     支払指図の生成後、管理者確認で「支払完了（模擬）」へ遷移し、完了通知とアンケート依頼を
#     アプリ内通知として送るF4フローを追加します。年間支払上限到達時は契約状態をcap_reachedに
#     更新し、管理者APIはBASIC認証で保護します。
#
# 上記を非エンジニアのユーザーテスト手順として次のように読み替えて自動化する:
#   手順1: 認証情報なし・誤った認証情報でPATCHを叩くと401になり、支払は完了しないこと
#   手順2: 正しいBASIC認証で「指図済」の支払をPATCHすると、支払が「支払完了（模擬）」になり、
#          利用者向けに2件のアプリ内通知（払い戻し完了・アンケート依頼）が生成されること
#   手順3: 年間の支払上限（2回）に達した場合、契約状態が「上限到達」になること
#   手順4: 同じ支払に対してもう一度操作しても、二重に通知が作られないこと（冪等性）
#   手順5: 「無効」な支払は完了操作を受け付けず、通知も作られないこと
#   手順6（セキュリティ・QC確認）: 存在しない支払IDでの操作は生の500ではなく404になること、
#          エラーメッセージはRailsの生スタックトレースを含まないこと、
#          このAPI経由でメールが送信・保存されることは一切ないこと（CLAUDE.md必須要件）
#
# 対象は開発環境のRailsアプリケーション（config/database.ymlのtest環境 = storage/test.sqlite3。
# 開発サーバーのdevelopment環境と同じSQLite）であり、本番サーバー・本番DB（PostgreSQL）へは
# 一切接続しない。BASIC認証情報（ADMIN_BASIC_USER / ADMIN_BASIC_PASSWORD）はテスト内で
# 開発環境の初期値（admin / changeme、.env.example記載の値）をスタブして使用する。
#
# 併せてQC10（エラーハンドリング）・OWASP10（A01 Broken Access Control、
# A07 Identification and Authentication Failures、A09 Security Logging and Monitoring
# Failures）の該当観点、およびCLAUDE.md必須要件「通知はアプリ内通知のみ（メール送信・
# 保存は禁止）」を確認する。
#
# 実行方法（開発/テストDBのみを対象。本番サーバーへは一切接続しない）:
#   cd src/backend
#   RAILS_ENV=test bin/rails db:test:prepare
#   bundle exec rspec ../../test/pr50/pr50_admin_payout_complete_spec.rb

require "rails_helper"

RSpec.describe "PR50: PATCH /admin/api/payouts/:id/complete（F4 支払完了・アプリ内通知）", type: :request do
  let(:admin_user) { "admin" }
  let(:admin_password) { "changeme" }
  let(:valid_auth_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:#{admin_password}")}" }
  end
  let(:wrong_password_headers) do
    { "Authorization" => "Basic #{Base64.strict_encode64("#{admin_user}:totally-wrong-password")}" }
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_USER").and_return(admin_user)
    allow(ENV).to receive(:[]).with("ADMIN_BASIC_PASSWORD").and_return(admin_password)

    # 設計資料1.7の契約状態マスタ（6件）・支払状態マスタ（3件）を用意する。
    # Payoutモデルのafter_saveコールバック（支払確定時の契約状態遷移）が
    # PolicyStatus.find_by!(code: "active"/"cap_reached"/"expired")等を参照するため、
    # 最小単位のマスタデータであっても全件そろえておく必要がある
    find_or_create_policy_status("waiting", "待機中")
    find_or_create_policy_status("active", "有効")
    find_or_create_policy_status("processing", "支払処理中")
    find_or_create_policy_status("cap_reached", "上限到達")
    find_or_create_policy_status("cancelled", "解約")
    find_or_create_policy_status("expired", "失効")
    find_or_create_payout_status("ordered", "指図済")
    find_or_create_payout_status("completed_simulated", "支払完了（模擬）")
    find_or_create_payout_status("invalid", "無効")
  end

  # ---------------------------------------------------------------------
  # 手順1: 認証情報の確認
  # ---------------------------------------------------------------------
  describe "手順1: BASIC認証" do
    it "認証情報なしでPATCHすると401になり、支払は完了しない" do
      user = User.create!(google_sub: "google-sub-pr50-auth-none")
      payout = build_ordered_payout_for(user, suffix: "auth-none")

      patch "/admin/api/payouts/#{payout.id}/complete"

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to match(/Basic/i)
      expect(payout.reload.payout_status.code).to eq("ordered")
      expect(Notification.count).to eq(0)
    end

    it "失敗パターン: 誤ったパスワードでも401になり、支払は完了しない" do
      user = User.create!(google_sub: "google-sub-pr50-auth-wrong")
      payout = build_ordered_payout_for(user, suffix: "auth-wrong")

      patch "/admin/api/payouts/#{payout.id}/complete", headers: wrong_password_headers

      expect(response).to have_http_status(:unauthorized)
      expect(payout.reload.payout_status.code).to eq("ordered")
    end
  end

  # ---------------------------------------------------------------------
  # 手順2: 正しい認証での支払完了と通知生成
  # ---------------------------------------------------------------------
  describe "手順2: 支払完了（模擬）操作とアプリ内通知" do
    it "「指図済」の支払をPATCHすると支払完了（模擬）になり、契約は有効に戻る" do
      user = User.create!(google_sub: "google-sub-pr50-complete")
      payout = build_ordered_payout_for(user, suffix: "complete")

      patch "/admin/api/payouts/#{payout.id}/complete", headers: valid_auth_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["payout"]).to include(
        "id" => payout.id,
        "payout_status_code" => "completed_simulated",
        "policy_status_code" => "active"
      )
      expect(payout.reload.payout_status.code).to eq("completed_simulated")
      expect(payout.policy.reload.policy_status.code).to eq("active")
    end

    it "支払完了と同時に「払い戻し完了」「アンケート依頼」の2件のアプリ内通知が、契約者本人宛に生成される" do
      user = User.create!(google_sub: "google-sub-pr50-notify")
      payout = build_ordered_payout_for(user, suffix: "notify")

      expect {
        patch "/admin/api/payouts/#{payout.id}/complete", headers: valid_auth_headers
      }.to change { Notification.count }.by(2)

      notifications = Notification.where(payout: payout).order(:id)
      expect(notifications.pluck(:kind)).to contain_exactly(
        Notification::KIND_PAYOUT_COMPLETED,
        Notification::KIND_SURVEY_REQUEST
      )
      expect(notifications.pluck(:user_id).uniq).to eq([ user.id ])
      expect(notifications.pluck(:policy_id).uniq).to eq([ payout.policy_id ])

      # 通知本文はハードコードではなくロケールファイル（ja.yml）の文言と一致すること
      completed_notification = notifications.find_by(kind: Notification::KIND_PAYOUT_COMPLETED)
      survey_notification = notifications.find_by(kind: Notification::KIND_SURVEY_REQUEST)
      expect(completed_notification.message).to eq(I18n.t("notifications.payout_completed", locale: :ja))
      expect(survey_notification.message).to eq(I18n.t("notifications.survey_request", locale: :ja))
    end
  end

  # ---------------------------------------------------------------------
  # 手順3: 年間支払上限到達時の契約状態遷移
  # ---------------------------------------------------------------------
  describe "手順3: 年間支払上限（2回）到達時は契約が「上限到達」になる" do
    it "同一契約で2回目の支払完了（模擬）を行うとcap_reachedへ遷移する" do
      user = User.create!(google_sub: "google-sub-pr50-cap-reached")
      plan = find_or_create_plan("seismic_pr50_cap_reached")
      station = find_or_create_station("seismic_tokyo_pr50_cap_reached")
      payout_tier = find_or_create_payout_tier("ten_thousand_pr50_cap_reached")
      processing_status = PolicyStatus.find_by!(code: "processing")

      policy = Policy.create!(
        user: user, plan: plan, station: station, payout_tier: payout_tier,
        policy_status: processing_status, threshold: "5強"
      )
      policy.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now)

      level = find_or_create_level("pr50_cap_reached", 6)

      first_observation = Observation.create!(
        station: station, event_id: "event-pr50-cap-reached-1", observed_at: 12.hours.ago,
        seismic_intensity_level: level, max_value: level.sort_order, simulated: true
      )
      first_payout = Payout.create!(
        policy: policy, payout_tier: payout_tier, payout_status: PayoutStatus.find_by!(code: "ordered"),
        observation: first_observation, idempotency_key: "policy_pr50_cap_reached_1", decided_at: Time.current
      )
      patch "/admin/api/payouts/#{first_payout.id}/complete", headers: valid_auth_headers
      expect(policy.reload.policy_status.code).to eq("active")

      second_observation = Observation.create!(
        station: station, event_id: "event-pr50-cap-reached-2", observed_at: 1.hour.ago,
        seismic_intensity_level: level, max_value: level.sort_order, simulated: true
      )
      second_payout = Payout.create!(
        policy: policy, payout_tier: payout_tier, payout_status: PayoutStatus.find_by!(code: "ordered"),
        observation: second_observation, idempotency_key: "policy_pr50_cap_reached_2", decided_at: Time.current
      )

      patch "/admin/api/payouts/#{second_payout.id}/complete", headers: valid_auth_headers

      expect(response).to have_http_status(:ok)
      expect(policy.reload.policy_status.code).to eq("cap_reached")
    end
  end

  # ---------------------------------------------------------------------
  # 手順4: 二重操作時の冪等性
  # ---------------------------------------------------------------------
  describe "手順4: 同じ支払を2回完了操作しても副作用が増えない（冪等性）" do
    it "既に支払完了（模擬）の支払へ再度PATCHしても200のままで通知は増えない" do
      user = User.create!(google_sub: "google-sub-pr50-idempotent")
      payout = build_ordered_payout_for(user, suffix: "idempotent")

      patch "/admin/api/payouts/#{payout.id}/complete", headers: valid_auth_headers
      expect(response).to have_http_status(:ok)
      expect(Notification.where(payout: payout).count).to eq(2)

      expect {
        patch "/admin/api/payouts/#{payout.id}/complete", headers: valid_auth_headers
      }.not_to change { Notification.count }

      expect(response).to have_http_status(:ok)
      expect(payout.reload.payout_status.code).to eq("completed_simulated")
    end
  end

  # ---------------------------------------------------------------------
  # 手順5: 無効な支払は完了操作を受け付けない
  # ---------------------------------------------------------------------
  describe "手順5: 「無効」な支払は完了操作できない" do
    it "invalid状態の支払をPATCHしても422で拒否され、通知も作られない" do
      user = User.create!(google_sub: "google-sub-pr50-invalid")
      payout = build_payout_for(user, suffix: "invalid", payout_status_code: "invalid")

      expect {
        patch "/admin/api/payouts/#{payout.id}/complete", headers: valid_auth_headers
      }.not_to change { Notification.count }

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq(I18n.t("admin_api.payouts.invalid_status_transition", locale: :ja))
      expect(payout.reload.payout_status.code).to eq("invalid")
    end
  end

  # ---------------------------------------------------------------------
  # 手順6: QC10・OWASP10・CLAUDE.md必須要件の確認
  # ---------------------------------------------------------------------
  describe "手順6: QC10・OWASP10・メール送信禁止の確認" do
    it "QC10 エラーハンドリング: 存在しない支払IDを操作すると生の500ではなく404になる" do
      patch "/admin/api/payouts/999999999/complete", headers: valid_auth_headers

      expect(response).to have_http_status(:not_found)
    end

    it "QC10 エラーハンドリング: 本番環境ではRailsの詳細エラーページ（スタックトレース付き）が無効化されている" do
      # 開発・テスト環境ではデバッグのため詳細なエラーページ（スタックトレース）を
      # あえて表示する設定になっている（development.md「デバッグトレースができるよう、
      # ログ・エラー情報を残すコードを書くこと」に対応）。一方で本番環境では利用者に
      # 内部実装（ファイルパス等）を露出しないよう無効化されている必要があるため、
      # 実際にリクエストを送るのではなく本番環境設定ファイルを静的に検証する
      production_config = File.read(Rails.root.join("config/environments/production.rb"))

      expect(production_config).to match(/config\.consider_all_requests_local\s*=\s*false/)
    end

    it "QC10 エラーハンドリング: 不正な状態遷移エラーはRailsの生スタックトレースを含まない" do
      user = User.create!(google_sub: "google-sub-pr50-error-message")
      payout = build_payout_for(user, suffix: "error-message", payout_status_code: "invalid")

      patch "/admin/api/payouts/#{payout.id}/complete", headers: valid_auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include("app/services")
      expect(response.body).not_to include(".rb:")
    end

    it "OWASP A01/A07: 他契約者の支払でも管理者認証さえ通れば操作できてしまうが、認証なしでは一切操作できない（BASIC認証が唯一の防波堤）" do
      user_a = User.create!(google_sub: "google-sub-pr50-owasp-a")
      payout_a = build_ordered_payout_for(user_a, suffix: "owasp-a")

      patch "/admin/api/payouts/#{payout_a.id}/complete"
      expect(response).to have_http_status(:unauthorized)
      expect(payout_a.reload.payout_status.code).to eq("ordered")
    end

    it "CLAUDE.md必須要件: 支払完了時に生成される通知はアプリ内通知（Notificationレコード）のみで、メール送信・保存は一切行われない" do
      # config/application.rbで action_mailer/railtie がrequireされていないため、
      # ActionMailer::Baseそのものがロードされていないことをまず確認する
      # （メール送信の実装が存在し得ないことのホワイトボックス確認）
      expect(defined?(ActionMailer::Base)).to be_nil

      # ExecutePayoutサービス・Notificationモデルのソースにメール送信APIへの
      # 参照が含まれないことを確認する（ハードコード検知に準じたブラックボックス確認）
      execute_payout_source = File.read(Rails.root.join("app/services/execute_payout.rb"))
      notification_source = File.read(Rails.root.join("app/models/notification.rb"))
      expect(execute_payout_source).not_to match(/deliver|ActionMailer|Mailer\.|mail\(/)
      expect(notification_source).not_to match(/deliver|ActionMailer|Mailer\.|mail\(/)

      user = User.create!(google_sub: "google-sub-pr50-no-email")
      payout = build_ordered_payout_for(user, suffix: "no-email")

      patch "/admin/api/payouts/#{payout.id}/complete", headers: valid_auth_headers

      expect(response).to have_http_status(:ok)
      expect(Notification.where(payout: payout).count).to eq(2)
    end
  end

  # ---------------------------------------------------------------------
  # 既知の設計上の課題（不具合ではないが要注意点として記録）
  # ---------------------------------------------------------------------
  describe "既知の設計上の課題: 通知本文の言語が契約者の選択言語ではなく管理者操作時のロケールで固定される" do
    it(
      "pending: 支払完了・アンケート依頼通知は7言語ぶんロケールファイルが用意されているにもかかわらず、" \
      "Admin::Authenticationのaround_actionが常にI18n.locale=:jaへ固定するため、" \
      "契約者が英語等でマイページを利用していても通知本文は常に日本語で保存されてしまう",
      pending: "Userモデルに選好言語（locale）が保存されておらず、通知本文が生成時点の" \
               "実行コンテキストのロケール（管理操作時は常に:ja）に依存する設計になっているため。" \
               "修正にはUserへのlocale永続化とNotification生成箇所でのロケール切り替えが必要で、" \
               "本PR(#50)の範囲を超えるため要設計判断。"
    ) do
      user = User.create!(google_sub: "google-sub-pr50-locale-bug")
      payout = build_ordered_payout_for(user, suffix: "locale-bug")

      # 事前にAPI呼び出し側のロケールを英語にしても、Admin::Authenticationの
      # around_action :use_japanese_locale がAdmin::Api::PayoutsController配下の
      # アクション全体を強制的に :ja へ固定するため、通知本文は常に日本語になる
      I18n.locale = :en
      patch "/admin/api/payouts/#{payout.id}/complete", headers: valid_auth_headers.merge("Accept-Language" => "en")

      completed_notification = Notification.find_by(payout: payout, kind: Notification::KIND_PAYOUT_COMPLETED)
      expect(completed_notification.message).to eq(I18n.t("notifications.payout_completed", locale: :en))
    ensure
      I18n.locale = I18n.default_locale
    end
  end

  # =======================================================================
  # フィクスチャ生成ヘルパー
  # =======================================================================

  def build_ordered_payout_for(user, suffix:)
    build_payout_for(user, suffix: suffix, payout_status_code: "ordered")
  end

  def build_payout_for(user, suffix:, payout_status_code:)
    plan = find_or_create_plan("seismic_pr50_#{suffix}")
    station = find_or_create_station("seismic_tokyo_pr50_#{suffix}")
    payout_tier = find_or_create_payout_tier("ten_thousand_pr50_#{suffix}")
    processing_status = PolicyStatus.find_by!(code: "processing")
    payout_status = PayoutStatus.find_by!(code: payout_status_code)
    level = find_or_create_level("pr50_shared_#{suffix}", 6)

    policy = Policy.create!(
      user: user, plan: plan, station: station, payout_tier: payout_tier,
      policy_status: processing_status, threshold: "5強"
    )
    policy.update_columns(waiting_until: 1.day.ago, expires_at: 1.year.from_now)

    observation = Observation.create!(
      station: station, event_id: "event-pr50-#{suffix}", observed_at: Time.current,
      seismic_intensity_level: level, max_value: level.sort_order, simulated: true
    )

    Payout.create!(
      policy: policy, payout_tier: payout_tier, payout_status: payout_status, observation: observation,
      idempotency_key: "policy_pr50_#{suffix}", decided_at: Time.current
    )
  end

  def next_sort_order(klass)
    (klass.maximum(:sort_order) || -1) + 1
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

  def find_or_create_policy_status(code, label_ja)
    PolicyStatus.find_by(code: code) || PolicyStatus.create!(
      code: code, sort_order: next_sort_order(PolicyStatus),
      **%i[label_ja label_en label_fr label_zh label_ru label_es label_ar].index_with { label_ja }
    )
  end

  def find_or_create_payout_status(code, label_ja)
    PayoutStatus.find_by(code: code) || PayoutStatus.create!(
      code: code, sort_order: next_sort_order(PayoutStatus),
      **%i[label_ja label_en label_fr label_zh label_ru label_es label_ar].index_with { label_ja }
    )
  end

  def find_or_create_level(code, sort_order)
    SeismicIntensityLevel.find_by(code: code) || SeismicIntensityLevel.create!(
      code: code, sort_order: sort_order.to_i.zero? ? next_sort_order(SeismicIntensityLevel) : sort_order,
      **%i[label_ja label_en label_fr label_zh label_ru label_es label_ar].index_with { "5強" }
    )
  end
end
