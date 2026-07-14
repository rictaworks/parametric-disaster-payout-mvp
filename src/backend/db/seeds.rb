# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

def seed_master_records(model, records)
  records.each do |attributes|
    model.find_or_create_by!(code: attributes.fetch(:code)) do |record|
      record.assign_attributes(attributes)
    end
  end
end

seed_master_records(
  Plan,
  [
    {
      code: "seismic",
      trigger_type: "seismic",
      label_ja: "震度連動",
      label_en: "Seismic-linked",
      label_fr: "Lié aux séismes",
      label_zh: "震度連動",
      label_ru: "Сейсмическая привязка",
      label_es: "Vinculado a sismos",
      label_ar: "مرتبط بالزلازل"
    },
    {
      code: "rainfall",
      trigger_type: "rainfall",
      label_ja: "降雨連動",
      label_en: "Rainfall-linked",
      label_fr: "Lié aux pluies",
      label_zh: "降雨連動",
      label_ru: "Привязка к осадкам",
      label_es: "Vinculado a lluvias",
      label_ar: "مرتبط بالأمطار"
    }
  ]
)

seed_master_records(
  SeismicIntensityLevel,
  [
    [ "0", "0" ],
    [ "1", "1" ],
    [ "2", "2" ],
    [ "3", "3" ],
    [ "4", "4" ],
    [ "5_weak", "5弱" ],
    [ "5_strong", "5強" ],
    [ "6_weak", "6弱" ],
    [ "6_strong", "6強" ],
    [ "7", "7" ]
  ].each_with_index.map do |(code, label_ja), index|
    {
      code: code,
      sort_order: index,
      label_ja: label_ja,
      label_en: code.tr("_", " "),
      label_fr: code.tr("_", " "),
      label_zh: code.tr("_", " "),
      label_ru: code.tr("_", " "),
      label_es: code.tr("_", " "),
      label_ar: code.tr("_", " ")
    }
  end
)

seed_master_records(
  Station,
  [
    {
      code: "seismic_tokyo",
      measurement_type: "seismic",
      label_ja: "東京震度観測点",
      label_en: "Tokyo seismic station",
      label_fr: "Station sismique de Tokyo",
      label_zh: "東京震度觀測站",
      label_ru: "Сейсмостанция Токио",
      label_es: "Estación sísmica de Tokio",
      label_ar: "محطة طوكيو الزلزالية"
    },
    {
      code: "seismic_osaka",
      measurement_type: "seismic",
      label_ja: "大阪震度観測点",
      label_en: "Osaka seismic station",
      label_fr: "Station sismique d'Osaka",
      label_zh: "大阪震度觀測站",
      label_ru: "Сейсмостанция Осаки",
      label_es: "Estación sísmica de Osaka",
      label_ar: "محطة أوساكا الزلزالية"
    },
    {
      code: "rainfall_tokyo",
      measurement_type: "rainfall",
      label_ja: "東京雨量観測点",
      label_en: "Tokyo rainfall station",
      label_fr: "Station pluviométrique de Tokyo",
      label_zh: "東京雨量觀測站",
      label_ru: "Дождемерная станция Токио",
      label_es: "Estación pluvial de Tokio",
      label_ar: "محطة طوكيو للأمطار"
    }
  ]
)

seed_master_records(
  PayoutTier,
  [
    {
      code: "ten_thousand",
      amount_yen: 10_000,
      label_ja: "1万円相当（模擬）",
      label_en: "Equivalent to JPY 10,000 (simulated)",
      label_fr: "Équivalent à 10 000 JPY (simulé)",
      label_zh: "相當於 10,000 日圓（模擬）",
      label_ru: "Эквивалент 10 000 иен (имитация)",
      label_es: "Equivalente a 10.000 JPY (simulado)",
      label_ar: "ما يعادل 10000 ين (محاكاة)"
    },
    {
      code: "thirty_thousand",
      amount_yen: 30_000,
      label_ja: "3万円相当（模擬）",
      label_en: "Equivalent to JPY 30,000 (simulated)",
      label_fr: "Équivalent à 30 000 JPY (simulé)",
      label_zh: "相當於 30,000 日圓（模擬）",
      label_ru: "Эквивалент 30 000 иен (имитация)",
      label_es: "Equivalente a 30.000 JPY (simulado)",
      label_ar: "ما يعادل 30000 ين (محاكاة)"
    }
  ]
)

seed_master_records(
  PolicyStatus,
  [
    {
      code: "pending",
      sort_order: 0,
      label_ja: "待機中",
      label_en: "Pending",
      label_fr: "En attente",
      label_zh: "待機中",
      label_ru: "Ожидание",
      label_es: "Pendiente",
      label_ar: "قيد الانتظار"
    },
    {
      code: "active",
      sort_order: 1,
      label_ja: "有効",
      label_en: "Active",
      label_fr: "Actif",
      label_zh: "有效",
      label_ru: "Активен",
      label_es: "Activo",
      label_ar: "نشط"
    },
    {
      code: "processing",
      sort_order: 2,
      label_ja: "支払処理中",
      label_en: "Processing payout",
      label_fr: "Traitement du paiement",
      label_zh: "支払處理中",
      label_ru: "Обработка выплаты",
      label_es: "Procesando pago",
      label_ar: "جارٍ معالجة الدفع"
    },
    {
      code: "cap_reached",
      sort_order: 3,
      label_ja: "上限到達",
      label_en: "Cap reached",
      label_fr: "Plafond atteint",
      label_zh: "達到上限",
      label_ru: "Лимит достигнут",
      label_es: "Tope alcanzado",
      label_ar: "تم بلوغ الحد"
    },
    {
      code: "cancelled",
      sort_order: 4,
      label_ja: "解約",
      label_en: "Cancelled",
      label_fr: "Résilié",
      label_zh: "解約",
      label_ru: "Отменён",
      label_es: "Cancelado",
      label_ar: "ملغى"
    },
    {
      code: "expired",
      sort_order: 5,
      label_ja: "失効",
      label_en: "Expired",
      label_fr: "Expiré",
      label_zh: "失效",
      label_ru: "Истёк",
      label_es: "Vencido",
      label_ar: "منتهي الصلاحية"
    }
  ]
)

seed_master_records(
  PayoutStatus,
  [
    {
      code: "ordered",
      sort_order: 0,
      label_ja: "指図済",
      label_en: "Ordered",
      label_fr: "Ordonné",
      label_zh: "已指示",
      label_ru: "Назначено",
      label_es: "Ordenado",
      label_ar: "تم الأمر"
    },
    {
      code: "completed_simulated",
      sort_order: 1,
      label_ja: "支払完了（模擬）",
      label_en: "Completed (simulated)",
      label_fr: "Terminé (simulé)",
      label_zh: "支払完成（模擬）",
      label_ru: "Завершено (имитация)",
      label_es: "Completado (simulado)",
      label_ar: "مكتمل (محاكاة)"
    },
    {
      code: "invalid",
      sort_order: 2,
      label_ja: "無効",
      label_en: "Invalid",
      label_fr: "Invalide",
      label_zh: "無効",
      label_ru: "Недействительно",
      label_es: "Inválido",
      label_ar: "غير صالح"
    }
  ]
)
