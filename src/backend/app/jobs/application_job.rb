class ApplicationJob < ActiveJob::Base
  # Solid Queue（本番の永続キューアダプター）自体には自動再試行機能がないため、
  # ActiveJob の retry_on で明示的に再試行させる。デッドロック・ロック待ちタイムアウト・
  # 接続確立失敗・コネクションプール枯渇は一時的な障害であることが多く、再試行により
  # 自動復旧できる可能性が高い一方、失敗したまま放置すると（観測の最大値が更新されない限り
  # 再取込では再判定されないため）該当する支払指図・通知が永久に欠落してしまう
  RETRYABLE_DATABASE_ERRORS = [
    ActiveRecord::Deadlocked,
    ActiveRecord::LockWaitTimeout,
    ActiveRecord::ConnectionNotEstablished,
    ActiveRecord::ConnectionTimeoutError
  ].freeze

  retry_on(*RETRYABLE_DATABASE_ERRORS, wait: :polynomially_longer, attempts: 5)

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
