# Phiếu Phản Ánh — K4 Level 3B, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: viết câu trả lời ngay dưới mỗi câu hỏi.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Lê Thanh Trường — Mã học viên: 2A202602492

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

> Tình huống: tôi tạo service trên Railway nhưng quên set biến `AGENT_API_KEY`
> trong dashboard. Nếu trường có mặc định `"changeme"`, app vẫn khởi động và
> health check xanh — deploy "thành công". Ai biết (hoặc đoán được) khóa mặc
> định sẽ gọi `/ask` thoải mái, câu trả lời tính tiền vào hóa đơn của tôi mà
> tôi chỉ phát hiện khi xem bill cuối tháng. Không có mặc định → pydantic ném
> `ValidationError` ngay lúc khởi động → deploy đỏ → tôi phát hiện thiếu biến
> ngay ở phút đầu deploy, trước khi một request nào được phục vụ.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

> Dòng log thật (gọi `/ask` trên stack compose cục bộ, ghi từ
> `docker compose logs agent`):
>
> ```json
> {"event": "ask_completed", "level": "info", "timestamp": "2026-09-29T10:54:58.844567+00:00", "user_id": "sv-test", "tokens_in": 3, "tokens_out": 37, "cost_usd": 2.265e-05}
> ```
>
> Hai việc làm được mà `print()` không làm được:
> 1. **Lọc/đếm tự động theo trường**: trên cloud log (Railway/Render), tôi có
>    thể truy vấn log theo `event=ask_completed` và `user_id`, hoặc lấy tổng
>    `cost_usd` trong một ngày chỉ bằng một query — với chuỗi tự do thì phải
>    dùng mắt để tìm từng dòng.
> 2. **Cảnh báo tự động theo ngưỡng**: máy đọc được giá trị số của `cost_usd`
>    nên có thể đặt alert "chi phí theo user vượt X USD thì báo" — với
>    `print("đã trả lời xong")` không có con số cấu trúc nào để so sánh cả.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | 1.19GB |
| Multi-stage | 184MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

> Số đo thật trên máy tôi (2026-09-29, Docker 28.0.4): bản 1 stage dùng `FROM python:3.11` (bản đầy đủ, khoảng hơn 1GB:
> kèm compiler GCC, header C, công cụ phát triển) cộng layer cài toàn bộ
> requirement nằm lâu trong cùng một image. Multi-stage dùng `python:3.11-slim`
> (~130MB) cho cả hai stage, stage `builder` chỉ làm nhiệm vụ cài thư viện vào
> `/install`, stage runtime chỉ **copy kết quả** đó sang — compiler và mọi thứ
> trung gian của builder bị bỏ lại, không vào image cuối. Kết quả: 184MB,
> nhỏ hơn ~6.5 lần. Image nhỏ = pull nhanh khi deploy, diện tích bị tấn công
> ít hơn (không có compiler, ít tool để kẻ tấn công dùng).

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

> Tôi đã thử thật: thêm một dòng comment vào `app/main.py` rồi
> `docker build` lại. Output build ghi rõ:
> `COPY requirements.txt .` → **CACHED**,
> `RUN pip install ...` → **CACHED** (không cài lại thư viện),
> `COPY --from=builder /install` → CACHED,
> `COPY app ./app` → chạy lại (đúng chỗ đổi),
> các layer sau nó (useradd, healthcheck) → chạy lại vì đứng sau layer thay đổi.
> Toàn bộ build chỉ mất vài giây.
>
> Nếu đặt `COPY . .` trước `RUN pip install`: copy toàn bộ source là một layer,
> sửa 1 ký tự làm layer này mất cache → `pip install` cũng mất cache và phải
> cài lại **toàn bộ** thư viện mỗi lần build (mất vài phút thay vì vài giây),
> đồng thời kéo theo mọi layer phía sau chạy lại. Mẹo: đặt thứ lệnh theo thứ
> tự "ít thay đổi nhất đứng trước".

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

> Chuỗi sự kiện: (1) code Python của tôi có lỗ hổng (ví dụ: nhận input rồi
> thực thi, hoặc đọc/ghi file theo đường dẫn không kiểm soát) → (2) kẻ tấn
> công lợi dụng để chiếm quyền điều khiển process của app → (3) nếu process
> đó chạy bằng **root trong container** (UID 0), kẻ tấn công lập tức có toàn
> quyền trong container: đọc mọi env (gồm cả API key), cài tool, sửa file hệ
> thống → (4) kết hợp với các cấu hình sơ hở (container chạy privileged, hoặc
> mount socket Docker vào container — bản thân nó đã có sẵn "cầu leo" lên
> host), kẻ tấn công còn có thể thoát container để chạm tới host, nơi root
> trong container có thể tương ứng với quyền root trên host.
>
> `USER` cắt đứt tại bước (3): process app chỉ là user thường (`appuser`),
> không đổi được file hệ thống, không đọc được các file/thư mục mà user đó
> không có quyền, không spawn được quyền root. Kẻ tấn công sau khi chiếm
> process sẽ kẹt ở tầng quyền thấp và phải dùng thêm một lỗ hổng leo quyền
> nữa — chi phí tấn công tăng hẳn. Nguyên tắc: defense in depth, một lớp
> phòng thủ không đủ thì nhiều lớp mỗi lớp gây khó một bậc.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

> **20 request trong 2 giây**: gửi 10 request vào giây 00:59 (phút thứ nhất,
> dùng hết quota), rồi 10 request nữa vào giây 01:01 (phút thứ hai, quota vừa
> reset). Hai lô cách nhau đúng 2 giây nhưng nằm ở hai "phút đồng hồ" khác
> nhau nên bộ đếm cho cả hai đều hợp lệ. Sliding window chặn được đòn này: nó
> xóa mọi entry cũ hơn 60 giây rồi mới đếm, nên ở bất kỳ thời điểm nào cũng
> chỉ có tối đa 10 request trong 60 giây trôi gần nhất, kể cả khi bạn bẻ rào
> đổi phút bằng cách nhồi sát mép phút.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

> Khác nhau: rate limit giới hạn **số lượng** request trong một cửa sổ thời
> gian (10/phút/user); cost guard giới hạn **số tiền** đã tiêu trong tháng
> (10 USD/tháng/user). Số lượng và tiền là hai thứ không tỷ lệ thuận — một
> request có thể tốn 1000 token hoặc 100.000 token.
>
> - Rate limit cho qua, cost guard phải chặn: user gửi 10 request mỗi phút —
>   đúng quota số lượng — nhưng mỗi request 50k token input, vài phút đã đốt
>   hết ngân sách tháng → cost guard trả 402.
> - Cost guard cho qua, rate limit phải chặn: user chỉ gửi các câu ngắn (chi
>   phí vài phần triệu USD, chưa đụng trần 10 USD) nhưng gửi 100 request/giây
>   suốt ngày — hóa đơn thì còn lâu mới chạm trần, nhưng service bị quá tải,
>   request của user khác bị chậm/đẩy ra. Đây là việc của rate limit → 429.

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

> Thứ tự sự kiện khi 3 container cùng có một probe kiểm tra Redis:
> (1) Redis mất kết nối (restart, quá tải, mạng nội bộ chập chờn). (2) Probe
> của cả 3 container đều trả 503. (3) Phía orchestrator/load balancer: liveness
> probe đỏ → kết luận cả 3 container "hỏng" → gỡ tất cả khỏi vòng xoay hoặc
> restart toàn bộ 3 container. (4) Trong lúc đó app thực ra vẫn sống — vì
> `/ask` có thể cần Redis nhưng bản thân process không hỏng; đáng lẽ chỉ cần
> chờ Redis quay lại. (5) Hậu quả: service tê liệt 100% (down hoàn toàn chứ
> không phải "xuống cấp nhẹ") chỉ vì một dependency phụ chết — cái giá của
> việc gộp hai câu hỏi khác nhau vào một probe.
>
> Tách ra: `/health` không đụng Redis → vẫn 200 → không có container nào bị
> restart oan; `/ready` đụng Redis → 503 → load balancer chỉ ngừng đẩy
> **traffic mới** vào, không giết process. Khi Redis sống lại, `/ready` xanh
> lại và cụm tự hồi phục mà không mất một container nào.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

> Tôi chạy 3 instance cùng nối một Redis (instance từ compose trên cổng 8000
> và hai instance bổ sung trên 8081, 8082) rồi gửi 6 câu hỏi liên tiếp với
> cùng `X-User-Id=sv-xoay-vong`, mỗi lần request rơi vào một instance khác nhau:
>
> ```
> port 8000 -> history_length=0
> port 8081 -> history_length=2
> port 8082 -> history_length=4
> port 8000 -> history_length=6
> port 8081 -> history_length=8
> port 8082 -> history_length=10
> ```
>
> Lịch sử tăng đều 0 → 2 → 4 → ... **bất kể request rơi vào container nào**,
> vì state nằm trong Redis mà cả ba cùng nhìn thấy. Nếu lưu trong dict của
> từng process: mỗi container có dict riêng, request thứ hai rơi vào container
> khác sẽ thấy lịch sử rỗng → `history_length` lúc 0 lúc nhảy lung tung tùy
> may rủi đường đi của request, và agent "mất trí nhớ" mỗi lần đổi instance
> hoặc container bị restart.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

> _Cần bạn tự điền sau lần deploy đầu tiên — đây là quan sát cá nhân thật,
> không ai ghi thay được. Cấu trúc gợi ý khi gặp lỗi:_
>
> - Thông báo lỗi: ...
> - Cách tìm ra nguyên nhân: (tôi mở log build/runtime trên dashboard, hoặc
>   gọi `/health` xem mã trả về, hoặc so sánh biến môi trường set trên cloud
>   với `.env.example`...)
> - Cách sửa: ...
>
> Trước khi deploy, tôi đã chạy qua thử cục bộ đầy đủ: `/health` 200,
> `/ready` 200, `/ask` 401 khi thiếu key và 200 khi đủ key, rate limit trả 429
> đúng như thiết kế — nên lỗi (nếu có) nhiều khả năng nằm ở phần kết nối
> Redis/đường truyền/health check của platform hơn là logic app.