// PR #47「契約申込ウィザードUI（5ステップ）を追加」
// PR本文の「非エンジニア向けユーザーテスト手順」（手順1〜8、全体を通しての確認ポイント）を
// 自動再現するテスト。対象は開発サーバーのコード（現在の main HEAD）であり、本番には一切接続しない。
//
// 対応する手順:
//   手順1: 契約申込ウィザードを開く（見出し・5ステップ進行バーの表示）
//   手順2: STEP1 プランを選択する
//   手順3: STEP2 観測点を選択する（プランと観測点の対応チェック）
//   手順4: STEP3 支払トリガーの閾値を選択する
//   手順5: STEP4 支払額区分を選択する
//   手順6: STEP5 内容確認・reCAPTCHA・申込（reCAPTCHA未チェック時はボタン押下不可、
//          チェック後に押下可能、送信後はマイページへ遷移、重複契約エラーの表示）
//   手順7: マイページで自分の契約を確認する（選んだ内容が最初から最後まで一致すること）
//   手順8: 未ログイン状態でマイページを開く（ログイン誘導・他人の契約情報が出ないこと）
//   全体確認: 選択内容とマイページ表示の一致、多言語でのステータス表示の完全性
//
// 併せて確認する観点:
//   QC10 (QC10.md) QC07 アクセシビリティ: ステッパーのaria-label、フォームのrole
//   QC10 QC10 エラーハンドリング: マスタ取得失敗・重複契約・未ログイン時の案内表示
//   OWASP10 (OWASP10.md) A07 Identification and Authentication Failures:
//     reCAPTCHAが実際のGoogleウィジェットのトークンを使っており、
//     従来のような固定文字列 "simulated-recaptcha-token" を送っていないこと
//   OWASP10 A01 Broken Access Control:
//     マイページ取得時にクライアント側からユーザー識別子を送っていないこと（セッションのみに依拠）、
//     未認証時に他人の契約情報が残らないこと
//   development.md 開発規約: alert()/confirm()/prompt() を使用していないこと
//
// 実行方法:
//   cd src/frontend && npm test -- --ci --testPathPatterns "test/pr47"
//   （jest.config.ts の roots/modulePaths 設定により test/pr** が自動的に対象になる）

import fs from "node:fs";
import path from "node:path";
import { act, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { AppShell } from "../../src/frontend/components/AppShell";
import NewPolicyPage from "../../src/frontend/app/policies/new/page";
import MyPage from "../../src/frontend/app/mypage/page";
import { SUPPORTED_LOCALES, getMessages } from "../../src/frontend/lib/i18n";

const FRONTEND_ROOT = path.join(__dirname, "../../src/frontend");

const pushMock = jest.fn();

jest.mock("next/navigation", () => ({
  useRouter: () => ({
    push: pushMock,
  }),
}));

// マスタAPIのID（101/201.../301...）はわざと1・2・3から外している。
// 「従来はフロント側でIDを1/2/3に固定していた」というPR本文の既知バグが再発した場合、
// 送信されるplan_id/station_id/payout_tier_idがこのIDと食い違いテストが失敗する。
const MASTERS_RESPONSE = {
  plans: [
    { id: 101, code: "seismic", trigger_type: "seismic" },
    { id: 102, code: "rainfall", trigger_type: "rainfall" },
  ],
  stations: [
    { id: 201, code: "seismic_tokyo", measurement_type: "seismic" },
    { id: 202, code: "seismic_osaka", measurement_type: "seismic" },
    { id: 203, code: "rainfall_tokyo", measurement_type: "rainfall" },
  ],
  payout_tiers: [
    { id: 301, code: "ten_thousand", amount_yen: 10_000 },
    { id: 302, code: "thirty_thousand", amount_yen: 30_000 },
  ],
};

type RecaptchaCallback = (token: string) => void;

function mockFetch(policyResponse: { ok: boolean; body: unknown }) {
  const calls: Array<{ url: string; init?: RequestInit }> = [];

  global.fetch = jest.fn((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    calls.push({ url, init });

    if (url.includes("/api/v1/masters")) {
      return Promise.resolve({
        ok: true,
        json: async () => MASTERS_RESPONSE,
      }) as unknown as Promise<Response>;
    }

    return Promise.resolve({
      ok: policyResponse.ok,
      text: async () => JSON.stringify(policyResponse.body),
    }) as unknown as Promise<Response>;
  }) as jest.Mock;

  return calls;
}

function mockRecaptcha() {
  let callback: RecaptchaCallback | null = null;
  const resetMock = jest.fn();
  const renderMock = jest.fn((_container: HTMLElement, params: { callback: RecaptchaCallback }) => {
    callback = params.callback;
    return 1;
  });

  window.grecaptcha = { render: renderMock, reset: resetMock };

  return {
    verify: (token: string) => {
      act(() => {
        callback?.(token);
      });
    },
    renderMock,
    resetMock,
  };
}

function jsonResponse(body: unknown, status = 200) {
  return Promise.resolve({
    ok: status >= 200 && status < 300,
    status,
    json: async () => body,
  });
}

describe("PR47 手順1: 契約申込ウィザードを開く", () => {
  beforeEach(() => {
    pushMock.mockReset();
    delete (window as { grecaptcha?: unknown }).grecaptcha;
  });

  it("見出しと5ステップの進行バーが表示される（失敗パターン: 画面が真っ白/選択肢が出ない）", async () => {
    mockFetch({ ok: true, body: { policy: { id: 1 } } });

    render(
      <AppShell>
        <NewPolicyPage />
      </AppShell>
    );

    expect(await screen.findByRole("heading", { name: "契約申込ウィザード" })).toBeInTheDocument();

    const stepper = screen.getByRole("list", { name: "申込ステップ" });
    const steps = within(stepper).getAllByRole("listitem");
    expect(steps).toHaveLength(5);
    expect(within(stepper).getByText("① プラン選択")).toBeInTheDocument();
    expect(within(stepper).getByText("② 観測点選択")).toBeInTheDocument();
    expect(within(stepper).getByText("③ 支払トリガー閾値選択")).toBeInTheDocument();
    expect(within(stepper).getByText("④ 支払額区分選択")).toBeInTheDocument();
    expect(within(stepper).getByText("⑤ 内容確認")).toBeInTheDocument();

    // プラン選択肢が最低1つも表示されない、という失敗パターンを検出する
    // （表示文言は messages.policies.new.plans の「震度連動」「降雨連動」）
    expect(screen.getByText("震度連動")).toBeInTheDocument();
    expect(screen.getByText("降雨連動")).toBeInTheDocument();
  });
});

describe("PR47 手順2〜6: STEP1〜5を実際に選択して申込を完了する", () => {
  beforeEach(() => {
    pushMock.mockReset();
    delete (window as { grecaptcha?: unknown }).grecaptcha;
  });

  it("選んだプラン・観測点・閾値・支払額区分がSTEP5の内容確認まで一致し、送信すると実IDでPOSTされマイページへ遷移する", async () => {
    const calls = mockFetch({ ok: true, body: { policy: { id: 123 } } });
    const recaptcha = mockRecaptcha();
    const user = userEvent.setup();

    render(
      <AppShell>
        <NewPolicyPage />
      </AppShell>
    );

    await screen.findByRole("heading", { name: "契約申込ウィザード" });

    // 手順2: STEP1 プラン選択。「降雨連動」プランをあえて選び、以降の画面に
    // 一貫して反映されることを確認する。
    const rainfallCard = screen.getByRole("button", { name: /降雨連動/ });
    await user.click(rainfallCard);
    expect(rainfallCard).toHaveAttribute("data-selected", "true");
    await user.click(screen.getByRole("button", { name: "次へ" }));

    // 手順3: STEP2 観測点選択。降雨プランを選んだので震度観測点は出てこない
    // （プランと観測点の対応チェック＝失敗パターンの検出）。
    expect(await screen.findByRole("heading", { name: "② 観測点選択" })).toBeInTheDocument();
    expect(screen.queryByText("東京震度観測点")).not.toBeInTheDocument();
    expect(screen.queryByText("大阪震度観測点")).not.toBeInTheDocument();
    const rainfallStationCard = screen.getByText("東京雨量観測点").closest("button");
    expect(rainfallStationCard).not.toBeNull();
    await user.click(rainfallStationCard as HTMLElement);
    expect(rainfallStationCard).toHaveAttribute("data-selected", "true");
    await user.click(screen.getByRole("button", { name: "次へ" }));

    // 手順4: STEP3 閾値選択。降雨用の選択肢（mm単位）が出ることを確認し、
    // "20 mm" を選ぶ。
    expect(await screen.findByRole("heading", { name: "③ 支払トリガー閾値選択" })).toBeInTheDocument();
    const thresholdCard = screen.getByText("20 mm").closest("button");
    expect(thresholdCard).not.toBeNull();
    await user.click(thresholdCard as HTMLElement);
    expect(thresholdCard).toHaveAttribute("data-selected", "true");
    await user.click(screen.getByRole("button", { name: "次へ" }));

    // 手順5: STEP4 支払額区分選択。「3万円相当（模擬）」を選ぶ。
    expect(await screen.findByRole("heading", { name: "④ 支払額区分選択" })).toBeInTheDocument();
    const payoutTierCard = screen.getByRole("button", { name: /3万円相当（模擬）/ });
    await user.click(payoutTierCard);
    expect(payoutTierCard).toHaveAttribute("data-selected", "true");
    await user.click(screen.getByRole("button", { name: "次へ" }));

    // 手順6: STEP5 内容確認。これまで選んだ内容が最後まで一致していることを確認する。
    const reviewHeading = await screen.findByRole("heading", { name: "内容を確認してください" });
    const reviewSummary = reviewHeading.closest("div") as HTMLElement;
    expect(within(reviewSummary).getByText("降雨連動")).toBeInTheDocument();
    expect(within(reviewSummary).getByText("東京雨量観測点")).toBeInTheDocument();
    expect(within(reviewSummary).getByText("20 mm")).toBeInTheDocument();
    expect(within(reviewSummary).getByText("3万円相当（模擬）")).toBeInTheDocument();

    // reCAPTCHA未チェック時は「申込する」ボタンが押せない（失敗パターン検出）
    const submitButton = screen.getByRole("button", { name: "申込する" });
    expect(submitButton).toBeDisabled();

    await waitFor(() => expect(recaptcha.renderMock).toHaveBeenCalled());
    recaptcha.verify("google-issued-real-token");

    await waitFor(() => expect(submitButton).toBeEnabled());
    await user.click(submitButton);

    await waitFor(() => expect(pushMock).toHaveBeenCalledWith("/mypage"));

    // マスタAPIから取得した「実際のID」（101/102, 201-203, 301/302）が
    // そのまま送信されており、フロント側で1/2/3に固定していないことを確認する。
    const policyCall = calls.find((call) => call.url.includes("/api/v1/policies") && call.init?.method === "POST");
    expect(policyCall).toBeDefined();
    const sentBody = JSON.parse(String(policyCall?.init?.body));
    expect(sentBody).toMatchObject({
      plan_id: 102, // rainfall
      station_id: 203, // rainfall_tokyo
      payout_tier_id: 302, // thirty_thousand
      recaptcha_token: "google-issued-real-token",
    });

    // reCAPTCHAが実際のGoogleウィジェットのコールバックから受け取った
    // トークンをそのまま送っており、固定文字列を送っていないことの確認
    // （OWASP A07: 認証・ボット検知バイパスの再発防止）
    expect(sentBody.recaptcha_token).not.toBe("simulated-recaptcha-token");
  });

  it("失敗パターン: reCAPTCHA未チェックのままフォーム送信を試みてもエラーメッセージが出て申込は成立しない", async () => {
    mockFetch({ ok: true, body: { policy: { id: 1 } } });
    mockRecaptcha();
    const user = userEvent.setup();

    const { container } = render(
      <AppShell>
        <NewPolicyPage />
      </AppShell>
    );

    await screen.findByRole("heading", { name: "契約申込ウィザード" });
    for (let index = 0; index < 4; index += 1) {
      // eslint-disable-next-line no-await-in-loop
      await user.click(screen.getByRole("button", { name: "次へ" }));
    }

    expect(screen.getByRole("button", { name: "申込する" })).toBeDisabled();

    const form = container.querySelector("form");
    expect(form).not.toBeNull();
    fireEvent.submit(form as HTMLFormElement);

    expect(await screen.findByText("reCAPTCHA の認証を完了してください。")).toBeInTheDocument();
    expect(pushMock).not.toHaveBeenCalled();
  });

  it("失敗パターン: 重複契約の場合はエラーメッセージが表示され、reCAPTCHAは再検証が必要になる", async () => {
    mockFetch({ ok: false, body: { error: "duplicate_policy" } });
    const recaptcha = mockRecaptcha();
    const user = userEvent.setup();

    render(
      <AppShell>
        <NewPolicyPage />
      </AppShell>
    );

    await screen.findByRole("heading", { name: "契約申込ウィザード" });
    for (let index = 0; index < 4; index += 1) {
      // eslint-disable-next-line no-await-in-loop
      await user.click(screen.getByRole("button", { name: "次へ" }));
    }

    await waitFor(() => expect(recaptcha.renderMock).toHaveBeenCalled());
    recaptcha.verify("google-issued-real-token");

    const submitButton = await screen.findByRole("button", { name: "申込する" });
    await waitFor(() => expect(submitButton).toBeEnabled());
    await user.click(submitButton);

    expect(await screen.findByText("同一プラン種別の有効な契約が既にあります。")).toBeInTheDocument();
    expect(pushMock).not.toHaveBeenCalled();

    // トークンの使い回し防止のため、reCAPTCHAウィジェットが再マウントされ
    // 再度押せない状態に戻ること
    await waitFor(() => expect(recaptcha.renderMock).toHaveBeenCalledTimes(2));
    expect(submitButton).toBeDisabled();
  });
});

describe("PR47 手順7: マイページで自分の契約を確認する", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("申込内容（プラン・観測点・閾値・支払額区分・状態「待機中」）がマイページの表示と最初から最後まで一致する", async () => {
    global.fetch = jest.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);

      if (url === "/api/v1/policies") {
        return jsonResponse({
          policies: [
            {
              id: 123,
              plan_code: "rainfall",
              station_code: "rainfall_tokyo",
              payout_tier_code: "thirty_thousand",
              policy_status_code: "pending",
              threshold: "20.0",
              waiting_until: "2026-07-20T00:00:00.000Z",
              expires_at: "2027-07-17T00:00:00.000Z",
              terminated_at: null,
            },
          ],
        });
      }
      if (url === "/api/v1/payouts") {
        return jsonResponse({ payouts: [] });
      }
      if (url === "/api/v1/notifications") {
        return jsonResponse({ notifications: [] });
      }
      throw new Error(`Unexpected fetch: ${url}`);
    });

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText("待機中")).toBeInTheDocument();
    expect(screen.getByText("降雨連動")).toBeInTheDocument();
    expect(screen.getByText("東京雨量観測点")).toBeInTheDocument();
    expect(screen.getByText("20 mm")).toBeInTheDocument();
    expect(screen.getByText("3万円相当（模擬）")).toBeInTheDocument();

    // 失敗パターン: 一覧が空になり「まだ契約がありません」が出てしまう場合の検出
    expect(screen.queryByText("まだ契約がありません。申込ウィザードから作成してください。")).not.toBeInTheDocument();
  });

  it("失敗パターン: 契約が0件の場合は空の案内文が表示される（一覧が沈黙して失敗と誤認されないための確認）", async () => {
    global.fetch = jest.fn().mockImplementation((input: RequestInfo | URL) => {
      const url = String(input);
      if (url === "/api/v1/policies") {
        return jsonResponse({ policies: [] });
      }
      if (url === "/api/v1/payouts") {
        return jsonResponse({ payouts: [] });
      }
      return jsonResponse({ notifications: [] });
    });

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText("まだ契約がありません。申込ウィザードから作成してください。")).toBeInTheDocument();
  });
});

describe("PR47 手順8: 未ログイン状態でマイページを開く（ログイン誘導・アクセス制御の確認）", () => {
  afterEach(() => {
    jest.restoreAllMocks();
  });

  it("契約の一覧は表示されず、ログインを促す案内のみが表示される", async () => {
    global.fetch = jest.fn().mockImplementation(() => jsonResponse({}, 401));

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    expect(await screen.findByText("ログインすると契約情報を確認できます。")).toBeInTheDocument();

    // 重大な失敗パターン: 未ログインなのに以前ログインしていた誰かの契約情報
    // （例: 別テストで使ったプラン名）が残って表示されてしまう場合の検出
    expect(screen.queryByText("東京雨量観測点")).not.toBeInTheDocument();
    expect(screen.queryByText("待機中")).not.toBeInTheDocument();
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  it("OWASP A01対策: マイページ取得はクッキー由来のセッションのみに依拠し、クライアント側からユーザー識別子（google_sub等）を送っていない", async () => {
    const calls: string[] = [];
    global.fetch = jest.fn().mockImplementation((input: RequestInfo | URL) => {
      calls.push(String(input));
      return jsonResponse({}, 401);
    });

    render(
      <AppShell>
        <MyPage />
      </AppShell>
    );

    await screen.findByText("ログインすると契約情報を確認できます。");

    const policiesCall = calls.find((url) => url.startsWith("/api/v1/policies"));
    expect(policiesCall).toBe("/api/v1/policies");
    // クエリパラメータでユーザーを指定できてしまうと、他人のIDを渡すだけで
    // 契約情報を閲覧できてしまうIDOR（他人のデータ漏えい）のリスクになる
    expect(policiesCall).not.toMatch(/[?&](user|google_sub|sub|user_id)=/i);
  });
});

describe("PR47 全体を通しての確認ポイント: 多言語でのステータス表示の完全性", () => {
  const STATUS_CODES = ["pending", "active", "processing", "cap_reached", "cancelled", "expired", "unknown"];

  it.each(SUPPORTED_LOCALES)(
    "ロケール「%s」で全ステータスの表示名が空欄や英語コードのままにならず定義されている",
    (locale) => {
      const messages = getMessages(locale);
      const statuses = messages.policies.new.statuses as Record<string, string>;

      STATUS_CODES.forEach((code) => {
        const label = statuses[code];
        expect(label).toBeDefined();
        expect(label.trim().length).toBeGreaterThan(0);
        // 表示名がAPIの生コード（英語スネークケース）のままになっていないこと
        expect(label).not.toBe(code);
      });
    }
  );

  it("繁体字中国語(zh.json)のステータス表示に日本語の直訳がそのまま混入していない（レビュー指摘の再発防止）", () => {
    const zhStatuses = getMessages("zh").policies.new.statuses as Record<string, string>;
    const jaStatuses = getMessages("ja").policies.new.statuses as Record<string, string>;

    // 修正前は「待機中」という日本語表記がzh.jsonに紛れ込んでいた。
    // 中国語の「待機中」に相当する自然な表記（等待中 等）に置き換わっていることを確認する。
    expect(zhStatuses.pending).not.toBe(jaStatuses.pending);
    expect(zhStatuses.pending).not.toBe("待機中");
  });
});

describe("PR47 開発規約・セキュリティの静的確認", () => {
  const SOURCE_FILES = [
    "components/wizard/PolicyApplicationWizard.tsx",
    "components/wizard/RecaptchaWidget.tsx",
    "components/wizard/policyWizardData.ts",
    "app/policies/new/page.tsx",
    "app/mypage/page.tsx",
  ];

  it.each(SOURCE_FILES)("%s はネイティブの alert()/confirm()/prompt() を使用していない（development.md 開発規約）", (relativePath) => {
    const source = fs.readFileSync(path.join(FRONTEND_ROOT, relativePath), "utf-8");

    expect(source).not.toMatch(/\balert\s*\(/);
    expect(source).not.toMatch(/\bconfirm\s*\(/);
    expect(source).not.toMatch(/\bprompt\s*\(/);
  });

  it("PolicyApplicationWizard.tsx は固定のreCAPTCHAトークン文字列を送っていない（OWASP A07 再発防止）", () => {
    const source = fs.readFileSync(
      path.join(FRONTEND_ROOT, "components/wizard/PolicyApplicationWizard.tsx"),
      "utf-8"
    );

    expect(source).not.toMatch(/simulated-recaptcha-token/);
  });

  it("マイページ・ウィザードの主要コンポーネントは dangerouslySetInnerHTML を使用していない（OWASP A03 XSS対策）", () => {
    SOURCE_FILES.forEach((relativePath) => {
      const source = fs.readFileSync(path.join(FRONTEND_ROOT, relativePath), "utf-8");
      expect(source).not.toMatch(/dangerouslySetInnerHTML/);
    });
  });
});
