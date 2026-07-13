Plan.find_or_create_by!(code: 'seismic') do |plan|
  plan.plan_type = 'seismic'
  plan.label_ja = '震度連動プラン'
  plan.label_en = 'Seismic Intensity Plan'
  plan.label_fr = 'Plan intensité sismique'
  plan.label_zh = '震度联动方案'
  plan.label_ru = 'План по сейсмической интенсивности'
  plan.label_es = 'Plan de intensidad sísmica'
  plan.label_ar = 'خطة شدة الزلازل'
end

Plan.find_or_create_by!(code: 'rainfall') do |plan|
  plan.plan_type = 'rainfall'
  plan.label_ja = '降雨連動プラン'
  plan.label_en = 'Rainfall Plan'
  plan.label_fr = 'Plan pluviométrique'
  plan.label_zh = '降雨联动方案'
  plan.label_ru = 'План по осадкам'
  plan.label_es = 'Plan por lluvia'
  plan.label_ar = 'خطة الأمطار'
end

[
  ['tokyo_seismic', 'seismic', '東京観測点', 'Tokyo Seismic Station', 'Tokyo'],
  ['osaka_seismic', 'seismic', '大阪観測点', 'Osaka Seismic Station', 'Osaka'],
  ['kochi_rainfall', 'rainfall', '高知観測点', 'Kochi Rainfall Station', 'Kochi']
].each do |code, plan_type, label_ja, label_en, prefecture|
  Station.find_or_create_by!(code: code) do |station|
    station.plan_type = plan_type
    station.label_ja = label_ja
    station.label_en = label_en
    station.label_fr = label_en
    station.label_zh = label_ja
    station.label_ru = label_en
    station.label_es = label_en
    station.label_ar = label_en
    station.prefecture = prefecture
  end
end

[
  ['tier_10k', 10_000, '10,000円相当（模擬）', 'JPY 10,000 equivalent (simulated)'],
  ['tier_30k', 30_000, '30,000円相当（模擬）', 'JPY 30,000 equivalent (simulated)']
].each do |code, amount_jpy, label_ja, label_en|
  PayoutTier.find_or_create_by!(code: code) do |tier|
    tier.amount_jpy = amount_jpy
    tier.label_ja = label_ja
    tier.label_en = label_en
    tier.label_fr = label_en
    tier.label_zh = label_ja
    tier.label_ru = label_en
    tier.label_es = label_en
    tier.label_ar = label_en
  end
end

[
  ['waiting', '待機中', 'Waiting'],
  ['active', '有効', 'Active'],
  ['processing', '支払処理中', 'Processing'],
  ['capped', '上限到達', 'Capped'],
  ['cancelled', '解約', 'Cancelled'],
  ['expired', '失効', 'Expired']
].each do |code, label_ja, label_en|
  PolicyStatus.find_or_create_by!(code: code) do |status|
    status.label_ja = label_ja
    status.label_en = label_en
  end
end

[
  ['int_0', '0', '0'],
  ['int_1', '1', '1'],
  ['int_2', '2', '2'],
  ['int_3', '3', '3'],
  ['int_4', '4', '4'],
  ['int_5_lower', '5弱', 'Lower 5'],
  ['int_5_upper', '5強', 'Upper 5'],
  ['int_6_lower', '6弱', 'Lower 6'],
  ['int_6_upper', '6強', 'Upper 6'],
  ['int_7', '7', '7']
].each do |code, label_ja, label_en|
  SeismicIntensityLevel.find_or_create_by!(code: code) do |level|
    level.label_ja = label_ja
    level.label_en = label_en
  end
end

[
  ['pending', '未処理', 'Pending'],
  ['approved', '承認済み', 'Approved'],
  ['rejected', '否認', 'Rejected']
].each do |code, label_ja, label_en|
  PayoutStatus.find_or_create_by!(code: code) do |status|
    status.label_ja = label_ja
    status.label_en = label_en
  end
end
