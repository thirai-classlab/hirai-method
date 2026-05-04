# SWE-bench task sandbox - claude-code-harness Phase C-1
# 単一コンテナで git clone + patch 適用 + (任意で) pytest 実行。
# claude-code CLI は host 側で実行し、生成 patch のみコンテナへ流し込む方式 (CLI 二重インストール回避)。
FROM python:3.11-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates curl build-essential \
    && rm -rf /var/lib/apt/lists/*

# 軽量に保つ。pytest は task ごとに repo の requirements を入れる方が再現性高い。
RUN pip install --upgrade pip setuptools wheel \
    && pip install pytest==8.3.3 unidiff==0.7.5

WORKDIR /work

# unprivileged user
RUN useradd -m -u 1000 swe && chown -R swe /work
USER swe

CMD ["bash"]
