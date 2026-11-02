# 統計シミュレーション・ノート：コードと結果

ブログの記事で使ったシミュレーションのコードと結果です。記事を公開するたびに、執筆用のリポジトリから自動で更新されます。

## 中身

| 場所 | 中身 |
| --- | --- |
| `posts/<slug>/PLAN.md` | 計画書（ADEMP 形式: 目的・データ生成・推定対象・手法・性能指標） |
| `posts/<slug>/config.yaml` | 条件表・反復数・seed |
| `posts/<slug>/model.R` | データ生成・解析・集計 |
| `posts/<slug>/test-model.R` | 単体テスト |
| `posts/<slug>/outputs/summary.csv` | 条件 × 手法 × 指標ごとの推定値とモンテカルロ標準誤差（MCSE） |
| `posts/<slug>/outputs/run_info.json` | seed、反復数、計算時間、R とパッケージの版などの実行記録 |
| `simkit/` | 共通の実行部品（乱数の割り当て、並列実行、途中保存、MCSE） |
| `env/` | 実行環境（Docker と R パッケージの一覧） |

`<slug>` は記事の URL の最後の部分と同じです。

## 再現する

Docker を使う場合（R とパッケージの版がそろうので推奨）:

```bash
make docker-build
make docker-sim SLUG=<slug> CORES=8
```

Docker を使わない場合は、R 4.6 系を入れてから:

```bash
Rscript env/install-packages.R
make sim SLUG=<slug> CORES=8
```

結果は `posts/<slug>/outputs/` に上書きされるので、`git diff` で公開されている結果と比べられます。
乱数は `config.yaml` の seed から条件 × 反復ごとに割り当てるので、並列数を変えても結果は変わりません。
反復数を減らした試運転は `PILOT=1` を付けます（結果は `posts/<slug>/results/pilot/` に出ます）。

## 注意

- `run_info.json` の `git.commit` は、非公開の執筆用リポジトリのコミットです。このリポジトリの各コミットのメッセージに、対応する執筆用リポジトリのコミットを書いています。
- `Makefile` のうち `new-post`、`push-results`、`site-dev`、`site-build` は執筆用リポジトリ向けで、ここでは使えません。
