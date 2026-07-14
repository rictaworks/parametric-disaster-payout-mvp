class RenameLegacySurveyResponseIsolationReason < ActiveRecord::Migration[7.2]
  class User < ActiveRecord::Base
    self.table_name = "users"
  end

  class LegacySurveyResponse < ActiveRecord::Base
    self.table_name = "legacy_survey_responses"
  end

  def up
    rename_column :legacy_survey_responses, :migration_error_reason, :isolation_reason

    # 外部キー追加前に、参照先ユーザーが既に削除済みの孤児アーカイブを整理する。
    # このテーブルは既に「移行できなかったデータの隔離アーカイブ」であり、
    # 本サービスは個人情報を保持しない方針のため、ユーザー削除後にレコードを残す理由がない。
    LegacySurveyResponse.where.not(user_id: User.select(:id)).delete_all

    # 元の 213247 では user_id に外部キーが張られていなかったため、ここで新規に追加する
    add_foreign_key :legacy_survey_responses, :users, on_delete: :cascade
  end

  def down
    remove_foreign_key :legacy_survey_responses, :users

    rename_column :legacy_survey_responses, :isolation_reason, :migration_error_reason
  end
end
