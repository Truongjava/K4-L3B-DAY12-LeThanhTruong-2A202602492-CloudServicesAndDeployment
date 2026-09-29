# ─────────────────────────────────────────────────────────
# CP2 — Containerization (multi-stage, non-root, healthcheck)
#
# Stage 1 `builder`: chỉ dùng để cài dependency vào /install.
#   - Không đưa compiler/uv vào stage runtime (image nhỏ hơn)
#   - COPY requirements.txt TRƯỚC khi pip install: Docker cache
#     theo layer, sửa code không phải cài lại thư viện
# Stage 2 (runtime): copy KẾT QUẢ từ builder sang + copy source.
#   - Base slim (gọn, vẫn có glibc chạy được binary wheel)
#   - Chạy bằng user thường `appuser`, không phải root
#   - HEALTHCHECK gọi /health để orchestrator biết trạng thái
#   - Cổng lấy từ biến môi trường $PORT (cloud tự gán)
# ─────────────────────────────────────────────────────────

FROM python:3.11-slim AS builder
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app ./app
COPY utils ./utils

RUN useradd --create-home appuser
USER appuser

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD python -c "import os,urllib.request;urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8000')+'/health', timeout=4)"

EXPOSE 8000

CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]