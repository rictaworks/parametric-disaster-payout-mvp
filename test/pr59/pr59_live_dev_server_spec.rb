# PR #59「READMEの最終整備とAPI参照の追加」
# 実際に開発サーバー（bin/rails server -e development）をTCPソケットで起動し、
# PR本文の非エンジニア向けテスト手順のうち、curlで実行する2つの手順を
# 「curlそのもの」に限りなく近い形（Net::HTTPでの実HTTPリクエスト）で再現する。
#
# 対応する手順:
#   手順6: （任意）curlでの自動ログイン手順を試す（セッション作成→契約一覧取得）
#     -> "手順6: セッション作成→契約一覧取得（実サーバー）" セクション
#
# 本ファイルは Rack::Test を使わず、実際に別プロセスで Rails サーバーを development
# 環境で起動し、Net::HTTP で本物のHTTPリクエストを送る点が
# pr59_readme_and_api_docs_spec.rb（Rack::Testベース）との違い。
# より高忠実度である一方、サーバー起動に数秒かかる・ポート競合の可能性があるため、
# 起動に失敗した場合はテストをスキップし、CI全体を巻き込まないようにしている。
#
# 対象は development 環境（自動ログインバイパスが Rails.env.development? 限定の
# ため development 環境でしか起動できない）だが、本ファイルのRSpecプロセス自身は
# RAILS_ENV=test で動作しており、ActiveRecordの接続先DBが別プロセス（spawnした
# development サーバー）とRSpecプロセスとで異なる（storage/development.sqlite3 と
# storage/test.sqlite3）。そのため本ファイルでは「RSpecプロセス側でActiveRecordの
# モデルを直接作成・参照する」検証は行わず、HTTPレスポンスの形だけを見る手順6の
# 2件（セッション作成／契約一覧取得、いずれもGETに近い読み取り中心の操作）に限定する。
# アンケート送信APIのエラーメッセージ検証（PR本文手順5相当）は、DB不整合を起こさず
# 同一プロセス内で完結する pr59_readme_and_api_docs_spec.rb 側で実施済み（Issue #61）。
#
# 本番サーバーには一切接続しない。development.sqlite3への書き込みは
# 「development-user」という自動ログインバイパス専用の決め打ちgoogle_subを
# find_or_create_byする1件のみで、これはローカルで手動起動して動作確認する際にも
# 同様に作成される想定済みのレコードであり、都度作成されるテスト固有データではない。
#
# [重要] 本ファイルはCI・bundle exec rspec の既定実行では自動的にスキップされる。
# development環境でRailsサーバーを起動するにはstorage/development.sqlite3に
# マイグレーション済みのスキーマが存在している必要があるが、CIランナーは
# RAILS_ENV=test のDBしか用意しないため、そのまま起動すると「スキーマ未整備」
# という別の理由で失敗し得る。かといって本ファイル側でdb:schema:loadを
# development.sqlite3に対して自動実行すると、force:cascadeによりテーブルが
# 再作成され、開発者がローカルで蓄積した開発用データを不用意に消してしまう
# 危険がある。そのため、既にマイグレーション済みのdevelopment環境を手元に
# 持っている開発者が明示的に検証したい場合のみ、環境変数
# PR59_RUN_LIVE_SERVER_SPEC=1 を指定して実行するオプトイン方式にしている。
#
# 実行方法（ローカルのdevelopment DBがマイグレーション済みであることを確認の上）:
#   cd src/backend
#   PR59_RUN_LIVE_SERVER_SPEC=1 RAILS_ENV=test bundle exec rspec ../../test/pr59/pr59_live_dev_server_spec.rb

require "rails_helper"
require "net/http"
require "socket"
require "open3"

RSpec.describe "PR59: 実開発サーバーに対するcurl相当の検証" do
  def find_free_port
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    server.close
    port
  end

  # 破壊的ではないが、development.sqlite3以外（本番向けDATABASE_URL経由の
  # 誤接続等）に対して自動ログインバイパス用ユーザーの作成等を行ってしまわ
  # ないよう、実際にサーバーを起動する前に接続先を検証する。
  def assert_local_sqlite_development_db!(spawn_env)
    check_script = "config = ActiveRecord::Base.configurations.configs_for(env_name: 'development').first; " \
                    "puts [config.adapter, config.database].join('|')"

    output, status = Open3.capture2(
      spawn_env, "bundle", "exec", "rails", "runner", check_script,
      chdir: @backend_root.to_s
    )

    raise "development環境の接続先確認に失敗しました: #{output}" unless status.success?

    adapter, database = output.strip.split("|")
    expected_path = @backend_root.join("storage", "development.sqlite3")
    actual_path = @backend_root.join(database.to_s)

    return if adapter == "sqlite3" && actual_path == expected_path

    raise "安全チェック失敗: development環境の接続先がローカルの#{expected_path}ではありません" \
          "（adapter=#{adapter}, database=#{actual_path}）。DATABASE_URL等の環境変数が接続先を" \
          "上書きしていないか確認してください。実サーバーの起動は中止します。"
  end

  def wait_for_boot(port, timeout: 25)
    deadline = Time.now + timeout
    loop do
      begin
        res = Net::HTTP.get_response(URI("http://127.0.0.1:#{port}/up"))
        return true if res.code.to_i == 200
      rescue Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError
        # サーバー起動待ち
      end
      return false if Time.now > deadline
      sleep 0.5
    end
  end

  before(:all) do
    @opted_in = ENV["PR59_RUN_LIVE_SERVER_SPEC"] == "1"
    next unless @opted_in

    @internal_api_secret = "pr59-live-dev-server-secret-#{SecureRandom.hex(4)}"
    @port = find_free_port
    @backend_root = Rails.root

    # Process.spawn の env ハッシュは、キーを列挙していない環境変数を
    # 親プロセス（このRSpecプロセス）からそのまま継承する。開発者のシェルに
    # 本番向け DATABASE_URL が設定されていると、development.sqlite3 の
    # 代わりにそちらへ接続してしまうため、値を nil にして明示的に除去する
    # （Process.spawn の仕様: 値が nil のキーは子プロセスの環境変数から削除される）。
    env = {
      "RAILS_ENV" => "development",
      "INTERNAL_API_SECRET" => @internal_api_secret,
      "PORT" => @port.to_s,
      "DATABASE_URL" => nil
    }

    assert_local_sqlite_development_db!(env)

    @pid = Process.spawn(
      env,
      "bundle", "exec", "rails", "server", "-p", @port.to_s, "-e", "development", "-b", "127.0.0.1",
      chdir: @backend_root.to_s,
      out: "/dev/null",
      err: "/dev/null"
    )

    @server_booted = wait_for_boot(@port)
  end

  after(:all) do
    next unless @opted_in

    if @pid
      begin
        Process.kill("TERM", @pid)
        Process.wait(@pid)
      rescue Errno::ESRCH, Errno::ECHILD
        # 既に終了している場合は何もしない
      end
    end
  end

  around(:each) do |example|
    if !@opted_in
      skip "既定ではスキップ（オプトイン制）。ローカルのdevelopment DBがマイグレーション済みであることを" \
           "確認した上で、PR59_RUN_LIVE_SERVER_SPEC=1 を指定して実行してください。"
    elsif @server_booted
      example.run
    else
      skip "開発サーバー（development環境）の起動に失敗またはタイムアウトしたためスキップします。" \
           "手動確認する場合は `bin/rails server -e development` を実行のうえ再実行してください。"
    end
  end

  def post_json(path, body, extra_headers: {})
    uri = URI("http://127.0.0.1:#{@port}#{path}")
    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["X-Internal-API-Secret"] = @internal_api_secret
    extra_headers.each { |k, v| request[k] = v }
    request.body = body.to_json

    Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
  end

  def get_json(path, extra_headers: {})
    uri = URI("http://127.0.0.1:#{@port}#{path}")
    request = Net::HTTP::Get.new(uri)
    request["X-Internal-API-Secret"] = @internal_api_secret
    extra_headers.each { |k, v| request[k] = v }

    Net::HTTP.start(uri.hostname, uri.port) { |http| http.request(request) }
  end

  # -----------------------------------------------------------------
  # 手順6: セッション作成→契約一覧取得（実サーバー）
  # -----------------------------------------------------------------
  describe "手順6: セッション作成→契約一覧取得（実サーバー）" do
    it "README「curlでの自動ログイン手順」の1つ目のコマンド相当（POST /api/v1/session）が実サーバーで200を返す" do
      response = post_json("/api/v1/session", {})

      expect(response.code.to_i).to eq(200)
      body = JSON.parse(response.body)
      expect(body["session_token"]).to be_present
    end

    it "README「curlでの自動ログイン手順」の2つ目のコマンド相当（GET /api/v1/policies）が実サーバーで200を返す" do
      session_response = post_json("/api/v1/session", {})
      session_token = JSON.parse(session_response.body)["session_token"]

      response = get_json("/api/v1/policies", extra_headers: { "X-Internal-Session-Token" => session_token })

      expect(response.code.to_i).to eq(200)
      expect(JSON.parse(response.body)).to have_key("policies")
    end
  end

end
