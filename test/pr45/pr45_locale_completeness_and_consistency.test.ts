// PR #45「フロントエンド基盤・多言語対応・BFFログイン導線を追加」
//
// CLAUDE.md必須要件「日本語・英語・フランス語・中国語・ロシア語・スペイン語・アラビア語の7言語に対応する」
// を裏付けるため、locales/*.json（ja/en/fr/zh/ru/es/ar）のキー構造が完全に一致しているか
// （欠落キー・余剰キーがないか）、および各値が空文字列でないかを機械的に確認する。
//
// また、翻訳の品質観点（QC10: 該当項目なし・独自追加のi18n一貫性チェック）として、
// 中国語ロケール(zh.json)内で簡体字/繁体字が混在していないかも確認する。
// このテストの後半ブロックは、現状のzh.jsonが実際に簡体字と繁体字を混在させて
// 使っている既知の品質バグを再現するテスト（red）であり、意図的に現状は失敗する。
//
// 実行方法:
//   cd src/frontend
//   npx jest --roots="<rootDir>" --roots="../../test/pr45" --modulePaths="<rootDir>/node_modules" -- pr45_locale_completeness_and_consistency

import fs from "node:fs";
import path from "node:path";
import { SUPPORTED_LOCALES } from "@/lib/i18n";
import ja from "@/locales/ja.json";
import en from "@/locales/en.json";
import fr from "@/locales/fr.json";
import zh from "@/locales/zh.json";
import ru from "@/locales/ru.json";
import es from "@/locales/es.json";
import ar from "@/locales/ar.json";

type LocaleMessages = typeof ja;

const messagesByLocale: Record<(typeof SUPPORTED_LOCALES)[number], LocaleMessages> = {
  ja,
  en,
  fr,
  zh,
  ru,
  es,
  ar,
};

function collectKeyPaths(value: unknown, prefix = ""): string[] {
  if (typeof value === "object" && value !== null && !Array.isArray(value)) {
    return Object.entries(value as Record<string, unknown>).flatMap(([key, nested]) =>
      collectKeyPaths(nested, prefix ? `${prefix}.${key}` : key)
    );
  }
  return [prefix];
}

function collectStringValues(value: unknown): string[] {
  if (typeof value === "string") {
    return [value];
  }
  if (typeof value === "object" && value !== null) {
    return Object.values(value as Record<string, unknown>).flatMap(collectStringValues);
  }
  return [];
}

describe("PR45: 7言語ロケールファイルのキー構造完全性", () => {
  const referenceKeyPaths = collectKeyPaths(ja).sort();

  it("locales/ 配下に7言語すべてのファイルが実在する（ja/en/fr/zh/ru/es/ar）", () => {
    const localesDir = path.resolve(__dirname, "../../src/frontend/locales");
    for (const locale of SUPPORTED_LOCALES) {
      expect(fs.existsSync(path.join(localesDir, `${locale}.json`))).toBe(true);
    }
  });

  it.each(SUPPORTED_LOCALES.filter((locale) => locale !== "ja"))(
    "%s.json は ja.json と完全に同じキー構造を持つ（欠落キー・余剰キーがない）",
    (locale) => {
      const keyPaths = collectKeyPaths(messagesByLocale[locale]).sort();
      expect(keyPaths).toEqual(referenceKeyPaths);
    }
  );

  it.each(SUPPORTED_LOCALES)("%s.json のすべての値が空文字列ではない（未翻訳の空欄がない）", (locale) => {
    const values = collectStringValues(messagesByLocale[locale]);
    const emptyValueCount = values.filter((value) => value.trim().length === 0).length;
    expect(emptyValueCount).toBe(0);
  });
});

describe("PR45（既知バグの再現・red）: 中国語ロケール(zh.json)内で簡体字と繁体字が混在していない", () => {
  // 同じ文字概念について、繁体字と簡体字のペアが両方とも zh.json 内に現れていないかを確認する。
  // 両方見つかった場合、そのファイル内で簡体字/繁体字の使い分けが一貫していないことを意味する。
  const traditionalToSimplifiedPairs: Array<[string, string]> = [
    ["導", "导"],
    ["覽", "览"],
    ["頁", "页"],
    ["讀", "读"],
    ["觀", "观"],
    ["測", "测"],
    ["約", "约"],
    ["給", "给"],
    ["區", "区"],
    ["門", "门"],
    ["狀", "状"],
    ["態", "态"],
    ["類", "类"],
    ["內", "内"],
    ["發", "发"],
    ["請", "请"],
    ["過", "过"],
  ];

  // 以前は簡体字と繁体字が混在していたが、現在は簡体字に統一されたため
  // 通常の it テストとして成功することを期待する。
  it("zh.json は簡体字・繁体字のどちらかに統一されている", () => {
    const zhSource = JSON.stringify(zh);
    const mixedPairs = traditionalToSimplifiedPairs.filter(
      ([traditionalChar, simplifiedChar]) =>
        zhSource.includes(traditionalChar) && zhSource.includes(simplifiedChar)
    );

    expect(mixedPairs).toEqual([]);
  });
});
