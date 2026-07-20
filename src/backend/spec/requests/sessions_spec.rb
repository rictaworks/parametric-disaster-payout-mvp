require "rails_helper"

RSpec.describe "API session endpoint", type: :request do
  let(:internal_api_secret) { "shared-secret" }
  let(:google_client_id) { "google-client-id" }
  let(:request_headers) { { "X-Internal-API-Secret" => internal_api_secret } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:[]).with("INTERNAL_API_SECRET").and_return(internal_api_secret)
    allow(ENV).to receive(:fetch).with("GOOGLE_CLIENT_ID").and_return(google_client_id)
  end

  it "creates a user from a valid Google ID token and returns an internal session token" do
    google_sub = "google-sub-123"

    allow(Google::Auth::IDTokens).to receive(:verify_oidc)
      .with("valid-token", aud: google_client_id)
      .and_return({
        "sub" => google_sub,
        "email" => "person@example.com",
        "name" => "Test Person"
      })

    post "/api/v1/session", params: { id_token: "valid-token" }, headers: request_headers

    expect(response).to have_http_status(:ok)

    body = JSON.parse(response.body)
    user = User.find_by!(google_sub: google_sub)

    expect(body["user"]).to eq(
      "id" => user.id,
      "google_sub" => google_sub
    )
    expect(body["session_token"]).to be_present
    # localeは個人情報ではなく多言語対応のための選好言語（Issue #65）。デフォルトは:ja
    expect(user.attributes.except("id", "google_sub", "created_at", "updated_at", "locale")).to be_empty
    expect(user.locale).to eq("ja")
    expect(User.column_names & %w[email name first_name last_name given_name family_name avatar_url phone_number]).to be_empty
  end

  it "returns the signed-in user for the current internal session token" do
    user = User.create!(google_sub: "google-sub-456")
    session_token = user.internal_session_token

    get "/api/v1/session", headers: request_headers.merge("X-Internal-Session-Token" => session_token)

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq(
      "user" => {
        "id" => user.id,
        "google_sub" => user.google_sub
      }
    )
  end

  it "returns 401 when no internal session token is present" do
    get "/api/v1/session", headers: request_headers

    expect(response).to have_http_status(:unauthorized)
  end

  it "returns 401 for an invalid Google ID token" do
    allow(Google::Auth::IDTokens).to receive(:verify_oidc)
      .and_raise(Google::Auth::IDTokens::VerificationError, "invalid token")

    post "/api/v1/session", params: { id_token: "invalid-token" }, headers: request_headers

    expect(response).to have_http_status(:unauthorized)
    expect(User.count).to eq(0)
  end

  it "returns 403 when the internal API secret does not match" do
    expect(Google::Auth::IDTokens).not_to receive(:verify_oidc)

    post "/api/v1/session",
      params: { id_token: "valid-token" },
      headers: request_headers.merge("X-Internal-API-Secret" => "wrong-secret")

    expect(response).to have_http_status(:forbidden)
    expect(User.count).to eq(0)
  end

  it "clears the browser session cookie and revokes session token when logging out" do
    user = User.create!(google_sub: "google-sub-logout")
    session_token = user.internal_session_token

    get "/api/v1/session", headers: request_headers.merge("X-Internal-Session-Token" => session_token)
    expect(response).to have_http_status(:ok)

    delete "/api/v1/session", headers: request_headers.merge("X-Internal-Session-Token" => session_token)

    expect(response).to have_http_status(:no_content)
    expect(response.headers["Set-Cookie"]).to include("parametric_session_token=")
    expect(response.headers["Set-Cookie"]).to include("Max-Age=0")

    get "/api/v1/session", headers: request_headers.merge("X-Internal-Session-Token" => session_token)
    expect(response).to have_http_status(:unauthorized)
  end

  it "clears the browser session cookie on logout even if the session token is invalid or missing" do
    delete "/api/v1/session", headers: request_headers.merge("X-Internal-Session-Token" => "invalid-token")

    expect(response).to have_http_status(:no_content)
    expect(response.headers["Set-Cookie"]).to include("parametric_session_token=")
    expect(response.headers["Set-Cookie"]).to include("Max-Age=0")
  end

  it "allows the development-only authentication bypass" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
    expect(Google::Auth::IDTokens).not_to receive(:verify_oidc)

    post "/api/v1/session", headers: request_headers

    expect(response).to have_http_status(:ok)
    expect(User.find_by!(google_sub: "development-user")).to be_present
  end

  it "does not enable the development bypass in production-like settings" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    allow(ENV).to receive(:[]).with("RAILS_ENV").and_return("development")

    post "/api/v1/session", headers: request_headers

    expect(response).to have_http_status(:unauthorized)
    expect(User.count).to eq(0)
  end
end
