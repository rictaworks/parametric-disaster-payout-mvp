# PR #59「READMEの最終整備とAPI参照の追加」
# PR本文に書かれた「非エンジニア向けユーザーテスト手順」を自動再現するテスト。
#
# 対応する手順:
#   手順1: READMEのプレースホルダーが埋まっているか確認する
#     -> "手順1: READMEのプレースホルダー解消" セクション
#   手順2: ブラウザでの自動ログイン手順を実際に試す（development分岐のバックエンド挙動）
#     -> "手順2: development環境の自動ログイン分岐" セクション
#   手順3: ページ一覧に載っているURLを実際に開いて確認する（フロントエンド側の実在確認）
#     -> "手順3: ページ一覧の実在確認" セクション
#   手順4: API一覧の表からSPEC/api/README.mdへのリンクをたどる
#     -> "手順4: API一覧のリンク整合性" セクション
#   手順5: アンケート送信APIのエラーメッセージが記載通りか確認する
#     -> "手順5: アンケート送信APIのエラーメッセージ" セクション
#   手順6: curlでの自動ログイン手順を試す（セッション作成→契約一覧取得）
#     -> "手順6: セッション作成→契約一覧取得のフロー" セクション
#     ※ 本ファイルは Rack::Test（RSpecのrequestスペック）で同じ経路を検証する。
#       実際にTCPソケットでRailsサーバーを起動してcurl相当のHTTPリクエストを送る
#       より高忠実度の検証は test/pr59/pr59_live_dev_server_spec.rb で行う。
#
# 実行方法（開発/テストDB・開発サーバーのみを対象。本番サーバーへは一切接続しない）:
#   cd src/backend
#   bundle exec rspec ../../test/pr59/pr59_readme_and_api_docs_spec.rb
#
# 併せて QC10（エラーハンドリング）/ OWASP10（A01 アクセス制御, A07 認証, A09 ログ・整合性）
# の該当観点も確認する。
#
# 実行結果メモ（作成時点）:
#   「手順5」内の [既知バグ・RED] マーカーの2件は pending（Issue #61）として扱い、
#   デフォルト実行（bundle exec rspec、CI含む）は green で完了する。修正が入って
#   予期せず成功した場合はRSpecが自動的に検知し失敗扱いにする。
#   なお、共有サンドボックス環境で他プロセスが同時に storage/test.sqlite3 へ書き込むと
#   SQLite3::BusyException: database is locked が一時的に発生することがある
#   （本テストのバグではない）。発生した場合は少し時間を置いてから再実行すること。

require "rails_helper"

RSpec.describe "PR59: READMEの最終整備とAPI参照の追加" do
  let(:repo_root) { Rails.root.join("..", "..") }
  let(:readme_path) { repo_root.join("README.md") }
  let(:spec_api_readme_path) { repo_root.join("SPEC", "api", "README.md") }
  let(:readme_body) { File.read(readme_path) }
  let(:spec_api_body) { File.read(spec_api_readme_path) }

  # GitHub の見出しアンカー生成規則を簡易再現する（英数・空白・ハイフン以外を除去し、空白をハイフンに変換）
  def github_anchor(heading_text)
    heading_text
      .downcase
      .gsub(/[^[[:alnum:]]\s_-]/, "")
      .strip
      .gsub(/\s+/, "-")
  end

  # -----------------------------------------------------------------
  # 手順1: READMEのプレースホルダー解消
  # -----------------------------------------------------------------
  describe "手順1: READMEのプレースホルダー解消" do
    it "README.md が存在する" do
      expect(File.exist?(readme_path)).to be(true)
    end

    it "「自動ログイン手順」「ページ一覧」「API 一覧」の3つの見出しが存在する" do
      %w[自動ログイン手順 ページ一覧 API\ 一覧].each do |heading|
        expect(readme_body).to match(/^#+\s*#{Regexp.escape(heading)}/), "見出し「#{heading}」が見つかりません"
      end
    end

    it "README.md に「（後続 Issue で記載）」というプレースホルダーが残っていない" do
      expect(readme_body).not_to include("後続 Issue で記載")
    end

    it "3つの見出しのすぐ下に具体的な内容（表やコード例）が書かれている（空欄でない）" do
      sections = readme_body.split(/^## /)
      target_headings = [ "自動ログイン手順", "ページ一覧", "API 一覧" ]

      target_headings.each do |heading|
        section = sections.find { |s| s.start_with?(heading) }
        expect(section).not_to be_nil, "セクション「#{heading}」が見つかりません"

        body_without_heading = section.sub(/\A.*\n/, "")
        expect(body_without_heading.strip.length).to be > 20, "セクション「#{heading}」の内容が空に近いです"
      end
    end
  end

  # -----------------------------------------------------------------
  # 手順2: development環境の自動ログイン分岐（バックエンド挙動の検証）
  #   README「2. development 環境の認証済み分岐」に書かれた fetch/curl の内容が
  #   実際のRailsの挙動と一致するかを、type: :requestで検証する。
  # -----------------------------------------------------------------
  describe "手順2: development環境の自動ログイン分岐", type: :request do
    let(:internal_api_secret) { "pr59-shared-secret" }
    let(:headers) { { "X-Internal-API-Secret" => internal_api_secret } }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
    end

    it "README記載どおり、id_tokenなしのPOST /api/v1/sessionで development-user が作成され200が返る" do
      post "/api/v1/session", params: {}, headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["session_token"]).to be_present
      expect(User.find_by(google_sub: "development-user")).to be_present
    end

    it "README記載どおり、発行されたセッションで /mypage 相当のAPI（契約一覧）にログイン画面へ飛ばされずアクセスできる" do
      post "/api/v1/session", params: {}, headers: headers
      session_token = JSON.parse(response.body)["session_token"]

      get "/api/v1/policies", headers: headers.merge("X-Internal-Session-Token" => session_token)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to have_key("policies")
    end

    it "セッショントークンなしでは /mypage 相当のAPIが401（=ログイン画面へ飛ばされる状態）になる（README失敗パターンの裏返し確認）" do
      get "/api/v1/policies", headers: headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  # -----------------------------------------------------------------
  # 手順3: ページ一覧の実在確認
  #   README「ページ一覧」表に載っている4画面が、フロントエンドの実ファイルとして存在するか確認する。
  #   （実際のブラウザ描画チェックは test/pr59/pr59_pages_list.test.tsx を参照）
  # -----------------------------------------------------------------
  describe "手順3: ページ一覧の実在確認" do
    it "README「ページ一覧」表に記載された4URLに対応するNext.jsページファイルが存在する" do
      frontend_app_dir = repo_root.join("src", "frontend", "app")

      expected_pages = {
        "ホーム" => frontend_app_dir.join("page.tsx"),
        "ログイン" => frontend_app_dir.join("login", "page.tsx"),
        "申込ウィザード" => frontend_app_dir.join("policies", "new", "page.tsx"),
        "マイページ" => frontend_app_dir.join("mypage", "page.tsx")
      }

      expected_pages.each do |name, path|
        expect(File.exist?(path)).to be(true), "「#{name}」に対応するページファイル #{path} が見つかりません"
      end
    end

    it "README「ページ一覧」の表に4行（ホーム/ログイン/申込ウィザード/マイページ）が存在する" do
      table_section = readme_body[/## ページ一覧.*?(?=\n## )/m]
      expect(table_section).not_to be_nil

      %w[ホーム ログイン 申込ウィザード マイページ].each do |page_name|
        expect(table_section).to include(page_name)
      end
    end
  end

  # -----------------------------------------------------------------
  # 手順4: API一覧のリンク整合性
  #   README「API 一覧」表の14個のリンクが、SPEC/api/README.md の実際の見出しに解決できるか確認する。
  # -----------------------------------------------------------------
  describe "手順4: API一覧のリンク整合性" do
    it "SPEC/api/README.md が存在する" do
      expect(File.exist?(spec_api_readme_path)).to be(true)
    end

    it "README「API 一覧」表に10個の利用者向けエンドポイントが記載されている" do
      table_section = readme_body[/## API 一覧.*/m]
      expect(table_section).not_to be_nil

      expected_endpoints = [
        "POST /api/v1/session",
        "PATCH /api/v1/locale",
        "GET /api/v1/masters",
        "GET /api/v1/policies",
        "POST /api/v1/policies",
        "PATCH /api/v1/policies/:id/cancel",
        "PATCH /api/v1/policies/:id/force_waiting_period_elapsed",
        "GET /api/v1/payouts",
        "GET /api/v1/notifications",
        "POST /api/v1/survey_responses"
      ]

      expected_endpoints.each do |endpoint|
        expect(table_section).to include(endpoint), "API一覧に #{endpoint} が見つかりません"
      end
    end

    it "README「API 一覧」表に4つの管理APIエンドポイントが記載されている" do
      table_section = readme_body[/## API 一覧.*/m]
      expect(table_section).not_to be_nil

      expected_admin_endpoints = [
        "POST /admin/simulated_events",
        "POST /admin/reset",
        "PATCH /admin/api/payouts/:id/complete",
        "PATCH /admin/api/payouts/:id/invalidate"
      ]

      expected_admin_endpoints.each do |endpoint|
        expect(table_section).to include(endpoint), "API一覧に #{endpoint} が見つかりません"
      end
    end

    it "README中の `SPEC/api/README.md#...` リンクが、SPEC/api/README.md内の実在する見出しへ解決できる" do
      # アンカーはハイフンだけでなくアンダースコアも含みうる
      # （例: force_waiting_period_elapsed）ため [a-z0-9_-]+ で抽出する
      links = readme_body.scan(%r{SPEC/api/README\.md#([a-z0-9_\-]+)}).flatten.uniq
      expect(links).not_to be_empty

      spec_headings = spec_api_body.scan(/^##\s+(.+)$/).flatten
      spec_anchors = spec_headings.map { |heading| github_anchor(heading) }

      links.each do |anchor|
        expect(spec_anchors).to include(anchor), "アンカー ##{anchor} に対応する見出しが SPEC/api/README.md にありません"
      end
    end

    it "README「API 一覧」の14エンドポイント（利用者向け10+管理API4）すべてに SPEC/api/README.md へのリンクが付与されている" do
      table_section = readme_body[/## API 一覧.*/m]
      # 表の各行は `[`...`](SPEC/api/README.md#...)` の形式のため、
      # 実際のリンクURL部分（`](...)` の中）だけを数える。
      # バッククォート付きのリンクラベル文字列自体にも同じ文字列が含まれるため、
      # 単純に "SPEC/api/README.md#" の出現回数を数えると2倍になってしまう点に注意。
      link_count = table_section.scan(%r{\]\(SPEC/api/README\.md#[a-z0-9_\-]+\)}).size

      expect(link_count).to eq(14)
    end

    it "SPEC/api/README.md に記載された14エンドポイント（利用者向け10+管理API4）が、実際のRailsルーティングに存在する（ドキュメントとコードの整合性）" do
      routes = Rails.application.routes.routes.map do |route|
        verb = route.verb.to_s
        path = route.path.spec.to_s.gsub(%r{\(\.:format\)\z}, "")
        [ verb, path ]
      end

      documented_endpoints = [
        [ "POST", "/api/v1/session" ],
        [ "PATCH", "/api/v1/locale" ],
        [ "GET", "/api/v1/masters" ],
        [ "GET", "/api/v1/policies" ],
        [ "POST", "/api/v1/policies" ],
        [ "PATCH", "/api/v1/policies/:id/cancel" ],
        [ "PATCH", "/api/v1/policies/:id/force_waiting_period_elapsed" ],
        [ "GET", "/api/v1/payouts" ],
        [ "GET", "/api/v1/notifications" ],
        [ "POST", "/api/v1/survey_responses" ],
        [ "POST", "/admin/simulated_events" ],
        [ "POST", "/admin/reset" ],
        [ "PATCH", "/admin/api/payouts/:id/complete" ],
        [ "PATCH", "/admin/api/payouts/:id/invalidate" ]
      ]

      documented_endpoints.each do |verb, doc_path|
        found = routes.any? do |route_verb, route_path|
          route_verb == verb && route_path == doc_path
        end
        expect(found).to be(true), "#{verb} #{doc_path} が実際のルーティングに存在しません"
      end
    end
  end

  # -----------------------------------------------------------------
  # 手順5: アンケート送信APIのエラーメッセージ
  #   PR本文で「Response data 満足度は必須入力です」に修正したと説明されている内容の実挙動確認。
  # -----------------------------------------------------------------
  describe "手順5: アンケート送信APIのエラーメッセージ", type: :request do
    let(:internal_api_secret) { "pr59-shared-secret" }
    let(:user) { User.create!(google_sub: "google-sub-pr59-survey") }
    let(:headers) do
      {
        "X-Internal-API-Secret" => internal_api_secret,
        "X-Internal-Session-Token" => user.internal_session_token
      }
    end

    let(:plan) do
      Plan.create!(
        code: "seismic_pr59_survey",
        trigger_type: "seismic",
        label_ja: "震度連動", label_en: "Seismic-linked", label_fr: "Seismic-linked",
        label_zh: "Seismic-linked", label_ru: "Seismic-linked", label_es: "Seismic-linked", label_ar: "Seismic-linked"
      )
    end
    let(:station) do
      Station.create!(
        code: "seismic_tokyo_pr59_survey",
        measurement_type: "seismic",
        label_ja: "東京震度観測点", label_en: "Tokyo seismic station", label_fr: "Tokyo seismic station",
        label_zh: "Tokyo seismic station", label_ru: "Tokyo seismic station", label_es: "Tokyo seismic station", label_ar: "Tokyo seismic station"
      )
    end
    let(:payout_tier) do
      PayoutTier.create!(
        code: "ten_thousand_pr59_survey",
        amount_yen: 10_000,
        label_ja: "1万円相当（模擬）", label_en: "Equivalent to JPY 10,000", label_fr: "Equivalent to JPY 10,000",
        label_zh: "Equivalent to JPY 10,000", label_ru: "Equivalent to JPY 10,000", label_es: "Equivalent to JPY 10,000", label_ar: "Equivalent to JPY 10,000"
      )
    end
    let!(:active_status) { PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "Active", label_fr: "Active", label_zh: "Active", label_ru: "Active", label_es: "Active", label_ar: "Active") }
    let!(:completed_payout_status) { PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "Completed", label_fr: "Completed", label_zh: "Completed", label_ru: "Completed", label_es: "Completed", label_ar: "Completed") }
    let!(:seismic_level) { SeismicIntensityLevel.find_or_create_by!(code: "5_strong_pr59_survey", sort_order: 6, label_ja: "5強", label_en: "5 strong", label_fr: "5 strong", label_zh: "5 strong", label_ru: "5 strong", label_es: "5 strong", label_ar: "5 strong") }

    let!(:policy) do
      Policy.create!(
        user: user, plan: plan, station: station, payout_tier: payout_tier,
        policy_status: active_status, threshold: "5強"
      ).tap { |p| p.update_columns(waiting_until: Time.current - 1.hour, expires_at: Time.current + 1.year) }
    end

    let!(:completed_payout) do
      Payout.create!(
        policy: policy,
        payout_tier: payout_tier,
        payout_status: completed_payout_status,
        observation: Observation.create!(
          station: station,
          event_id: "event-pr59-survey",
          observed_at: Time.current,
          seismic_intensity_level: seismic_level,
          max_value: 5,
          simulated: false
        ),
        idempotency_key: "policy_#{policy.id}_event-pr59-survey",
        decided_at: Time.current
      )
    end

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    end

    it "PR本文の再現curlどおり、satisfaction未入力だと『Response data 満足度は必須入力です』を返す" do
      post "/api/v1/survey_responses",
        params: { payout_id: completed_payout.id, response_data: {} }.to_json,
        headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to eq([ "Response data 満足度は必須入力です" ])
    end

    it "SPEC/api/README.mdに記載されたエラーメッセージ文字列と実際のレスポンスが完全一致する" do
      documented_message = spec_api_body[/```json\s*\{\s*"error":\s*\[\s*"([^"]+)"/m, 1]
      expect(documented_message).to eq("Response data 満足度は必須入力です")

      post "/api/v1/survey_responses",
        params: { payout_id: completed_payout.id, response_data: {} }.to_json,
        headers: headers.merge("Content-Type" => "application/json")

      expect(JSON.parse(response.body)["error"]).to eq([ documented_message ])
    end

    it "I18n.default_localeが:enでも、アンケート送信APIは日本語の検証メッセージを返す" do
      expect(I18n.default_locale).to eq(:en)

      post "/api/v1/survey_responses",
        params: { payout_id: completed_payout.id, response_data: {} }.to_json,
        headers: headers.merge("Content-Type" => "application/json")

      expect(JSON.parse(response.body)["error"]).to eq([ "Response data 満足度は必須入力です" ])
    end

    it "I18n.with_locale(:ja) 下でも、response_data:{} はsatisfaction_requiredのみを返す" do
      I18n.with_locale(:ja) do
        post "/api/v1/survey_responses",
          params: { payout_id: completed_payout.id, response_data: {} }.to_json,
          headers: headers.merge("Content-Type" => "application/json")
      end

      expect(JSON.parse(response.body)["error"]).to eq([ "Response data 満足度は必須入力です" ])
    end

    it "『満足度は必須入力です』という完全な日本語表記（Response dataが付かない誤記載）にはならない（README記載の失敗パターンの否定）" do
      post "/api/v1/survey_responses",
        params: { payout_id: completed_payout.id, response_data: {} }.to_json,
        headers: headers.merge("Content-Type" => "application/json")

      body = JSON.parse(response.body)
      expect(body["error"]).not_to eq([ "満足度は必須入力です" ])
    end

    it "PRの注記どおり、response_data の日本語属性ラベル（activerecord.attributes.survey_response.response_data）は未定義である（英語表記が混じる根本原因の裏付け）" do
      ja_yaml = YAML.load_file(Rails.root.join("config", "locales", "ja.yml"), aliases: true)
      attribute_label = ja_yaml.dig("ja", "activerecord", "attributes", "survey_response", "response_data")

      expect(attribute_label).to be_nil
    end

    it "満足度が正しく送信された場合は201で成功する（ドキュメントの成功例との整合性）" do
      post "/api/v1/survey_responses",
        params: { payout_id: completed_payout.id, response_data: { satisfaction: 5, feedback: "満足" } }.to_json,
        headers: headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["survey_response"]["response_data"]["satisfaction"]).to eq(5)
    end
  end

  # -----------------------------------------------------------------
  # 手順6: セッション作成→契約一覧取得のフロー（curl相当をRack::Testで検証）
  # -----------------------------------------------------------------
  describe "手順6: セッション作成→契約一覧取得のフロー", type: :request do
    let(:internal_api_secret) { "pr59-shared-secret" }
    let(:headers) { { "X-Internal-API-Secret" => internal_api_secret } }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
    end

    it "README「curlでの自動ログイン手順」の1つ目のコマンド相当（セッション作成）が200を返す" do
      post "/api/v1/session", params: {}, headers: headers
      expect(response).to have_http_status(:ok)
    end

    it "README「curlでの自動ログイン手順」の2つ目のコマンド相当（契約一覧取得）が200かつJSONの契約一覧を返す" do
      post "/api/v1/session", params: {}, headers: headers
      session_token = JSON.parse(response.body)["session_token"]

      get "/api/v1/policies", headers: headers.merge("X-Internal-Session-Token" => session_token)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["policies"]).to eq([])
    end
  end

  # -----------------------------------------------------------------
  # QC10 / OWASP10 該当観点の追加確認
  # -----------------------------------------------------------------
  describe "QC10 / OWASP10 該当観点", type: :request do
    let(:internal_api_secret) { "pr59-shared-secret" }

    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    end

    it "QC10 エラーハンドリング: 存在しないAPIパスへのアクセスはスタックトレースを含む生の500ではなく404を返す" do
      get "/api/v1/not_a_real_endpoint", headers: { "X-Internal-API-Secret" => internal_api_secret }

      expect(response).to have_http_status(:not_found)
    end

    it "OWASP A01 アクセス制御: 他ユーザーのpayoutに対するアンケート送信は403で拒否される（マイページ同様、自分のデータのみ参照・更新可）" do
      owner = User.create!(google_sub: "google-sub-pr59-owner")
      attacker = User.create!(google_sub: "google-sub-pr59-attacker")

      plan = Plan.create!(
        code: "seismic_pr59_acl", trigger_type: "seismic",
        label_ja: "震度連動", label_en: "x", label_fr: "x", label_zh: "x", label_ru: "x", label_es: "x", label_ar: "x"
      )
      station = Station.create!(
        code: "seismic_pr59_acl", measurement_type: "seismic",
        label_ja: "観測点", label_en: "x", label_fr: "x", label_zh: "x", label_ru: "x", label_es: "x", label_ar: "x"
      )
      payout_tier = PayoutTier.create!(
        code: "pr59_acl_tier", amount_yen: 10_000,
        label_ja: "1万円", label_en: "x", label_fr: "x", label_zh: "x", label_ru: "x", label_es: "x", label_ar: "x"
      )
      active_status = PolicyStatus.find_or_create_by!(code: "active", sort_order: 1, label_ja: "有効", label_en: "x", label_fr: "x", label_zh: "x", label_ru: "x", label_es: "x", label_ar: "x")
      completed_status = PayoutStatus.find_or_create_by!(code: "completed_simulated", sort_order: 1, label_ja: "支払完了（模擬）", label_en: "x", label_fr: "x", label_zh: "x", label_ru: "x", label_es: "x", label_ar: "x")
      seismic_level = SeismicIntensityLevel.find_or_create_by!(code: "5_strong_pr59_acl", sort_order: 6, label_ja: "5強", label_en: "x", label_fr: "x", label_zh: "x", label_ru: "x", label_es: "x", label_ar: "x")

      owner_policy = Policy.create!(
        user: owner, plan: plan, station: station, payout_tier: payout_tier,
        policy_status: active_status, threshold: "5強"
      ).tap { |p| p.update_columns(waiting_until: Time.current - 1.hour, expires_at: Time.current + 1.year) }

      owner_payout = Payout.create!(
        policy: owner_policy, payout_tier: payout_tier, payout_status: completed_status,
        observation: Observation.create!(
          station: station, event_id: "event-pr59-acl", observed_at: Time.current,
          seismic_intensity_level: seismic_level, max_value: 5, simulated: false
        ),
        idempotency_key: "policy_#{owner_policy.id}_event-pr59-acl",
        decided_at: Time.current
      )

      post "/api/v1/survey_responses",
        params: { payout_id: owner_payout.id, response_data: { satisfaction: 5 } }.to_json,
        headers: {
          "X-Internal-API-Secret" => internal_api_secret,
          "X-Internal-Session-Token" => attacker.internal_session_token,
          "Content-Type" => "application/json"
        }

      expect(response).to have_http_status(:forbidden)
      expect(SurveyResponse.where(payout_id: owner_payout.id)).to be_empty
    end

    it "OWASP A07 認証の欠陥: 内部API共有シークレットが一致しないと develpment分岐であっても403で拒否される" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

      post "/api/v1/session", params: {}, headers: { "X-Internal-API-Secret" => "wrong-secret" }

      expect(response).to have_http_status(:forbidden)
    end

    it "OWASP A02/A08 シークレット管理: .env.example に実際のシークレット値が書かれておらずプレースホルダーのままである" do
      env_example_path = repo_root.join("src", "backend", ".env.example")
      expect(File.exist?(env_example_path)).to be(true)

      content = File.read(env_example_path)
      expect(content).to include("INTERNAL_API_SECRET=change-this-to-a-random-secret")
      expect(content).not_to match(/INTERNAL_API_SECRET=(?!change-this-to-a-random-secret).+/)
    end
  end
end
