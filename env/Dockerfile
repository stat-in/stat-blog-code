# syntax=docker/dockerfile:1
# シミュレーションの実行環境（R）。
# リポジトリはビルドに含めず、実行時に /work へマウントする（env/compose.yaml）。
FROM rocker/r-ver:4.6.2

# R パッケージは Posit Package Manager の日付スナップショットから入れる。
# この日付を変えない限り、いつ・どこでビルドしても同じ版が入る。
# 変えるときは env/install-packages.R の日付もそろえる。
ARG CRAN_SNAPSHOT=2026-10-28

RUN apt-get update && apt-get install -y --no-install-recommends git make \
    && rm -rf /var/lib/apt/lists/*

RUN echo "options(repos = c(CRAN = 'https://p3m.dev/cran/__linux__/resolute/${CRAN_SNAPSHOT}'))" \
      >> "${R_HOME}/etc/Rprofile.site"
COPY env/r-packages.txt /tmp/r-packages.txt
RUN Rscript -e 'pkgs <- trimws(sub("#.*", "", readLines("/tmp/r-packages.txt"))); \
      pkgs <- pkgs[nzchar(pkgs)]; install.packages(pkgs); \
      stopifnot(all(pkgs %in% rownames(installed.packages())))'

RUN git config --system --add safe.directory '*'

ENV HOME=/tmp \
    SIM_IMAGE="rocker/r-ver:4.6.2 + CRAN ${CRAN_SNAPSHOT}"

WORKDIR /work
CMD ["bash"]
