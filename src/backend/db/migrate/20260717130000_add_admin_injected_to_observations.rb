class AddAdminInjectedToObservations < ActiveRecord::Migration[7.2]
  def up
    add_column :observations, :admin_injected, :boolean, null: false, default: false

    # Temporarily define the models in the migration namespace to ensure they are isolated.
    observation_model = Class.new(ActiveRecord::Base) do
      self.table_name = "observations"
    end
    observation_event_model = Class.new(ActiveRecord::Base) do
      self.table_name = "observation_events"
    end

    # デプロイ前に管理画面（Admin::SimulatedEventsController, F5）から注入された
    # 既存の simulated: true レコードは、このカラム追加だけでは一律 admin_injected:
    # false になり、一覧・続報検索・未処理の再評価ジョブから見えなくなってしまう。
    # 管理画面注入は payload に station_id（Station の主キー）を使い、気象庁
    # ポーリング（JmaPoller）は payload に station_code（気象庁コード文字列）を
    # 使うため、履歴（observation_events.payload）にどちらのキーが含まれるかで
    # 発生源を判別してバックフィルする。
    observation_model.where(simulated: true).find_each do |observation|
      admin_injected = observation_event_model
        .where(observation_id: observation.id)
        .any? { |event| event.payload.is_a?(Hash) && event.payload.key?("station_id") }

      observation.update_column(:admin_injected, true) if admin_injected
    end
  end

  def down
    remove_column :observations, :admin_injected
  end
end
