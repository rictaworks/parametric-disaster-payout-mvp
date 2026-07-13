# 本サービスは保険（デモ）であり実際の金銭のお支払いは発生しません。
# マスタデータ合計26件（Plans:2, SeismicIntensityLevels:10, Stations:3, PayoutTiers:2, PolicyStatuses:6, PayoutStatuses:3）

# Plans（震度連動／降雨連動）: 2件
Plan.find_or_create_by!(code: "seismic_plan") do |p|
  p.plan_type = "seismic"
  p.labels = JSON.generate({
    ja: "震度連動プラン（デモ）",
    en: "Seismic Intensity Plan (Demo)",
    fr: "Plan sismique (Démo)",
    zh: "地震烈度计划（演示）",
    ru: "Сейсмический план (Демо)",
    es: "Plan sísmico (Demo)",
    ar: "خطة الزلازل (تجريبي)"
  })
end

Plan.find_or_create_by!(code: "rainfall_plan") do |p|
  p.plan_type = "rainfall"
  p.labels = JSON.generate({
    ja: "降雨連動プラン（デモ）",
    en: "Rainfall Plan (Demo)",
    fr: "Plan de précipitations (Démo)",
    zh: "降雨计划（演示）",
    ru: "Дождевой план (Демо)",
    es: "Plan de lluvia (Demo)",
    ar: "خطة الأمطار (تجريبي)"
  })
end

# SeismicIntensityLevels（震度0〜7）: 10件
seismic_levels = [
  { code: "0",       numeric_value: 0.0,  ja: "震度0",    en: "Intensity 0" },
  { code: "1",       numeric_value: 1.0,  ja: "震度1",    en: "Intensity 1" },
  { code: "2",       numeric_value: 2.0,  ja: "震度2",    en: "Intensity 2" },
  { code: "3",       numeric_value: 3.0,  ja: "震度3",    en: "Intensity 3" },
  { code: "4",       numeric_value: 4.0,  ja: "震度4",    en: "Intensity 4" },
  { code: "5_lower", numeric_value: 4.5,  ja: "震度5弱",  en: "Intensity 5 Lower" },
  { code: "5_upper", numeric_value: 5.0,  ja: "震度5強",  en: "Intensity 5 Upper" },
  { code: "6_lower", numeric_value: 5.5,  ja: "震度6弱",  en: "Intensity 6 Lower" },
  { code: "6_upper", numeric_value: 6.0,  ja: "震度6強",  en: "Intensity 6 Upper" },
  { code: "7",       numeric_value: 7.0,  ja: "震度7",    en: "Intensity 7" }
]

seismic_levels.each do |lvl|
  SeismicIntensityLevel.find_or_create_by!(code: lvl[:code]) do |s|
    s.numeric_value = lvl[:numeric_value]
    s.labels = JSON.generate({
      ja: lvl[:ja], en: lvl[:en], fr: lvl[:en],
      zh: lvl[:ja], ru: lvl[:en], es: lvl[:en], ar: lvl[:en]
    })
  end
end

# Stations（震度観測点2・雨量観測点1）: 3件
Station.find_or_create_by!(code: "seismic_station_1") do |s|
  s.station_type = "seismic"
  s.labels = JSON.generate({
    ja: "震度観測点A（デモ）",   en: "Seismic Station A (Demo)",
    fr: "Station sismique A (Démo)", zh: "地震站A（演示）",
    ru: "Сейсмическая станция A (Демо)", es: "Estación sísmica A (Demo)",
    ar: "محطة زلزالية A (تجريبي)"
  })
end

Station.find_or_create_by!(code: "seismic_station_2") do |s|
  s.station_type = "seismic"
  s.labels = JSON.generate({
    ja: "震度観測点B（デモ）",   en: "Seismic Station B (Demo)",
    fr: "Station sismique B (Démo)", zh: "地震站B（演示）",
    ru: "Сейсмическая станция B (Демо)", es: "Estación sísmica B (Demo)",
    ar: "محطة زلزالية B (تجريبي)"
  })
end

Station.find_or_create_by!(code: "rainfall_station_1") do |s|
  s.station_type = "rainfall"
  s.labels = JSON.generate({
    ja: "雨量観測点A（デモ）",       en: "Rainfall Station A (Demo)",
    fr: "Station pluviométrique A (Démo)", zh: "雨量站A（演示）",
    ru: "Дождевая станция A (Демо)", es: "Estación de lluvia A (Demo)",
    ar: "محطة أمطار A (تجريبي)"
  })
end

# PayoutTiers（1万円相当・3万円相当、いずれも模擬）: 2件
PayoutTier.find_or_create_by!(code: "tier_10k") do |t|
  t.amount_yen = 10_000
  t.labels = JSON.generate({
    ja: "模擬支払 1万円相当（デモ）", en: "Simulated 10,000 JPY (Demo)",
    fr: "Simulation 10 000 JPY (Démo)", zh: "模拟1万日元（演示）",
    ru: "Имитация 10 000 JPY (Демо)", es: "Simulación 10,000 JPY (Demo)",
    ar: "محاكاة 10,000 ين (تجريبي)"
  })
end

PayoutTier.find_or_create_by!(code: "tier_30k") do |t|
  t.amount_yen = 30_000
  t.labels = JSON.generate({
    ja: "模擬支払 3万円相当（デモ）", en: "Simulated 30,000 JPY (Demo)",
    fr: "Simulation 30 000 JPY (Démo)", zh: "模拟3万日元（演示）",
    ru: "Имитация 30 000 JPY (Демо)", es: "Simulación 30,000 JPY (Demo)",
    ar: "محاكاة 30,000 ين (تجريبي)"
  })
end

# PolicyStatuses（待機中・有効・支払処理中・上限到達・解約・失効）: 6件
policy_statuses = [
  { code: PolicyStatus::WAITING,     ja: "待機中",     en: "Waiting" },
  { code: PolicyStatus::ACTIVE,      ja: "有効",       en: "Active" },
  { code: PolicyStatus::PROCESSING,  ja: "支払処理中", en: "Processing" },
  { code: PolicyStatus::CAP_REACHED, ja: "上限到達",   en: "Cap Reached" },
  { code: PolicyStatus::CANCELLED,   ja: "解約",       en: "Cancelled" },
  { code: PolicyStatus::LAPSED,      ja: "失効",       en: "Lapsed" }
]

policy_statuses.each do |ps|
  PolicyStatus.find_or_create_by!(code: ps[:code]) do |s|
    s.labels = JSON.generate({
      ja: ps[:ja], en: ps[:en], fr: ps[:en],
      zh: ps[:ja], ru: ps[:en], es: ps[:en], ar: ps[:en]
    })
  end
end

# PayoutStatuses（指図済・支払完了（模擬）・無効）: 3件
payout_statuses = [
  { code: PayoutStatus::INSTRUCTED, ja: "指図済",           en: "Instructed" },
  { code: PayoutStatus::COMPLETED,  ja: "支払完了（模擬）", en: "Completed (Simulated)" },
  { code: PayoutStatus::VOIDED,     ja: "無効",             en: "Voided" }
]

payout_statuses.each do |ps|
  PayoutStatus.find_or_create_by!(code: ps[:code]) do |s|
    s.labels = JSON.generate({
      ja: ps[:ja], en: ps[:en], fr: ps[:en],
      zh: ps[:ja], ru: ps[:en], es: ps[:en], ar: ps[:en]
    })
  end
end

total = [ Plan, SeismicIntensityLevel, Station, PayoutTier, PolicyStatus, PayoutStatus ].map(&:count).sum
puts "マスタデータ合計: #{total}件（期待値: 26件）"
