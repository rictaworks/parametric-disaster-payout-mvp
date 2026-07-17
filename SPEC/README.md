# SPEC/

仕様書・リバースエンジニアリング資料（ER図・DFD・シーケンス図・クラス図・状態遷移図・ユースケース図、Mermaid記法）を管理する。

- 初期設計資料（設計時点の意図）: [../parametric-disaster-payout-mvp_design_document.md](../parametric-disaster-payout-mvp_design_document.md)
- 実装リバースエンジニアリング図（DBスキーマの実体を反映、随時更新）:
  - ER図: [er_diagram.md](er_diagram.md)
- API仕様メモ: [api/README.md](api/README.md)

DFD・シーケンス図・クラス図・状態遷移図・ユースケース図は現時点では初期設計資料のものを正としている（実装との乖離が生じた場合は本ディレクトリ配下に更新版をMermaidで追加すること）。テーブル・カラム名など実装と直接対応する内容は必ず `er_diagram.md` の実装リバースエンジニアリング図を参照する。
