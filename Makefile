# 統計ブログ: 作業の入口。`make help` で一覧を表示する。
SHELL := /bin/bash
.DEFAULT_GOAL := help

# PC ごとの設定（並列数など）は local.mk に書く（Git 管理外）。例: CORES = 15
-include local.mk

SLUG ?=
CORES ?= $(shell echo $$(( ($$(nproc 2>/dev/null || echo 2) + 1) / 2 )))
POST := posts/$(SLUG)
RSCRIPT ?= Rscript
RUN_FLAGS = $(if $(PILOT),--pilot) $(if $(FRESH),--fresh) $(if $(ALLOW_DIRTY),--allow-dirty)
DOCKER_RUN = HOST_UID=$$(id -u) HOST_GID=$$(id -g) docker compose -f env/compose.yaml run --rm sim

.PHONY: help check-slug new-post sim test push-results site-dev site-build \
        docker-build docker-sim docker-test docker-shell

help:
	@echo "記事とシミュレーション"
	@echo "  make new-post SLUG=<slug>                 雛形から新しいテーマを作る"
	@echo "  make sim SLUG=<slug> [PILOT=1] [CORES=n]  実行（PILOT=1 で少ない反復の試運転）"
	@echo "  make test [SLUG=<slug>]                   simkit と各テーマのテスト"
	@echo "  make push-results SLUG=<slug>             outputs/ をコミットして push"
	@echo ""
	@echo "Docker（本番の実行はこちらを推奨）"
	@echo "  make docker-build                         実行環境のイメージを作る"
	@echo "  make docker-sim SLUG=<slug> [CORES=n]     Docker の中で sim を実行"
	@echo "  make docker-test                          Docker の中で test を実行"
	@echo "  make docker-shell                         Docker の中でシェルを開く"
	@echo ""
	@echo "サイト"
	@echo "  make site-dev                             手元でサイトを表示（http://localhost:4321）"
	@echo "  make site-build                           サイトをビルド"
	@echo ""
	@echo "いまの並列数: CORES=$(CORES)（local.mk で変えられる）"

check-slug:
	@test -n "$(SLUG)" || { echo "SLUG=<slug> を指定してください"; exit 1; }
	@test -f "$(POST)/model.R" || { echo "$(POST)/model.R がありません"; exit 1; }

new-post:
	@test -n "$(SLUG)" || { echo "SLUG=<slug> を指定してください"; exit 1; }
	@test ! -e "$(POST)" || { echo "$(POST) はすでにあります"; exit 1; }
	mkdir -p $(POST)
	cp posts/_template/{PLAN.md,config.yaml,model.R,test-model.R,article.mdx} $(POST)/
	sed -i.bak 's/__SLUG__/$(SLUG)/' $(POST)/config.yaml && rm $(POST)/config.yaml.bak
	@echo "$(POST) を作りました。PLAN.md から書き始めてください。"

sim: check-slug
	$(RSCRIPT) simkit/run.R $(POST) --cores $(CORES) $(RUN_FLAGS)

test:
	$(RSCRIPT) -e 'testthat::test_dir("simkit/tests", stop_on_failure = TRUE)'
	@for f in $(if $(SLUG),$(POST)/test-model.R,$(wildcard posts/*/test-model.R)); do \
	  echo "== $$f"; \
	  $(RSCRIPT) -e "testthat::test_file('$$f', reporter = 'summary', stop_on_failure = TRUE)" || exit 1; \
	done

push-results: check-slug
	@test -f $(POST)/outputs/run_info.json || { echo "本番の結果がありません（make docker-sim SLUG=$(SLUG)）"; exit 1; }
	git add $(POST)/outputs
	git commit -m "results($(SLUG)): 本番の実行結果"
	git push origin HEAD

site-dev:
	npm install && npm run dev

site-build:
	npm install && npm run build

docker-build:
	docker compose -f env/compose.yaml build

docker-sim: check-slug
	$(DOCKER_RUN) make sim SLUG=$(SLUG) CORES=$(CORES) PILOT=$(PILOT) FRESH=$(FRESH) ALLOW_DIRTY=$(ALLOW_DIRTY)

docker-test:
	$(DOCKER_RUN) make test

docker-shell:
	$(DOCKER_RUN) bash
