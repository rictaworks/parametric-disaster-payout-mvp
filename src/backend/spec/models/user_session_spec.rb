require "rails_helper"

RSpec.describe UserSession, type: :model do
  let(:user) { User.create!(google_sub: "test-user-sub") }

  describe ".generate_for_user" do
    it "creates a new session and returns session record and raw token" do
      session, raw_token = UserSession.generate_for_user(user)

      expect(session).to be_persisted
      expect(session.user).to eq(user)
      expect(session.token_digest).to eq(Digest::SHA256.hexdigest(raw_token))
      expect(session.expires_at).to be > Time.current
      expect(session.revoked_at).to be_nil
    end
  end

  describe "session limits and cleanup" do
    it "removes expired and revoked sessions when generating a new session" do
      session1, _raw1 = UserSession.generate_for_user(user, expires_in: -1.hour)
      session2, _raw2 = UserSession.generate_for_user(user)
      session2.revoke!

      _new_session, _raw_new = UserSession.generate_for_user(user)

      expect(UserSession.exists?(session1.id)).to be false
      expect(UserSession.exists?(session2.id)).to be false
    end

    it "enforces maximum active session limit per user by deleting oldest active session" do
      12.times do
        UserSession.generate_for_user(user)
      end

      expect(user.user_sessions.active.count).to eq(UserSession::MAX_ACTIVE_SESSIONS_PER_USER)
      expect(user.user_sessions.count).to eq(UserSession::MAX_ACTIVE_SESSIONS_PER_USER)
    end

    it "enforces active session limit concurrently without exceeding maximum count" do
      threads = Array.new(15) do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            UserSession.generate_for_user(user)
          end
        end
      end
      threads.each(&:join)

      expect(user.user_sessions.active.count).to eq(UserSession::MAX_ACTIVE_SESSIONS_PER_USER)
    end
  end

  describe ".find_active_by_token" do
    it "finds an active session by raw token" do
      session, raw_token = UserSession.generate_for_user(user)

      found = UserSession.find_active_by_token(raw_token)
      expect(found).to eq(session)
    end

    it "returns nil when token is blank or invalid" do
      expect(UserSession.find_active_by_token(nil)).to be_nil
      expect(UserSession.find_active_by_token("invalid_token")).to be_nil
    end

    it "returns nil when session is revoked" do
      session, raw_token = UserSession.generate_for_user(user)
      session.revoke!

      expect(UserSession.find_active_by_token(raw_token)).to be_nil
    end

    it "returns nil when session is expired" do
      session, raw_token = UserSession.generate_for_user(user, expires_in: -1.hour)

      expect(UserSession.find_active_by_token(raw_token)).to be_nil
    end
  end

  describe "#revoke!" do
    it "sets revoked_at to current time" do
      session, _raw_token = UserSession.generate_for_user(user)
      expect(session.active?).to be true

      session.revoke!
      expect(session.revoked_at).to be_present
      expect(session.active?).to be false
    end
  end
end
