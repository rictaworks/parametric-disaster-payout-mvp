# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## プロジェクト概要

震度・降雨量という客観的パラメータのみで即日**模擬支払**判定を行うパラメトリック災害保険のMVP（需要調査目的）。実際の金銭は支払わない。仕様の詳細（機能要件・ER図・DFD・シーケンス図・状態遷移図・ユースケース図）は @parametric-disaster-payout-mvp_design_document.md を参照。

- スタック：Next.js（TypeScript）+ Rails（Ruby）。DB は本番 PostgreSQL、開発 SQLite
- 認証：Google ログインのみ。個人情報（氏名・メール等）は保持せず、opaque な `google_sub` のみ保持する
- サービス内で常に「保険（デモ）」「模擬支払」であることを明示すること（法規制上必須）
- 通知はアプリ内通知のみ（メール送信・保存は禁止）

## ブランチ・PR ルール

- main ブランチでの直接作業は禁止。ただし `src/*` 以外のファイルは main への直接 push を許可する
- `src/*` の変更は必ず PR を作成すること
- PR は日本語で記述し、非エンジニア向けのユーザーテスト手順を本文に丁寧に書くこと
- commit 前に必ず security review を実施すること（@.claude/OWASP10.md 参照）

## 開発フロー（TDD 厳守）

`plan → red test → coding → green test` の順を厳守する。Rails 側は RSpec、Next.js 側は Jest。フロント確認は curl / `wget --mirror` / Playwright を用いる。環境変数は `.env` を参照する。テスト観点は @.claude/TM.md、品質は @.claude/QC10.md、セキュリティは @.claude/OWASP10.md を参照。

詳細な開発ルールは `.claude/rules/` 以下（development.md / architecture.md / workflow.md）を参照。CLAUDE.md と併せて自動的に読み込まれる。

## 削除系コマンドの禁止（重要）

以下のルールはこのワークスペース内のすべての会話で絶対に守られる：

- Claude はファイルまたはディレクトリを削除するコマンドを一切生成してはならない。
  例：rm, rm -rf, rm *, rmdir, unlink, cache --delete,
      lftp mirror --delete, rsync --delete, git clean -df, find -delete 等。

- 削除が必要な場合でも、Claude は削除コマンドを提案せず、
  「手動で削除してください」といった説明に留めること。

- 削除の推奨・削除操作の自動判断も禁止。

- ssh / lftp / デプロイ系スクリプトを生成する場合でも、
  削除コマンドの生成は禁止。

これらはすべての会話・コード生成に適用される。

## シークレット管理（重要）

- `config/master.key` など機密ファイルを `git add` するコードを生成してはならない
- デプロイスクリプト・セットアップ手順でも同様
- シークレットは必ず環境変数（RAILS_MASTER_KEY 等）で渡すこと
- `.gitignore` への追加を確認する手順を必ずコードに含めること
- 初回コミット前に `git status` でステージング確認を促すこと