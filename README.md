# SDLC kit: quy trình phát triển phần mềm tự động với Claude Code

Bộ kit cài vào một repo để Claude **tự làm việc nhưng có cổng chặn cứng**:

- Claude nhận task từ issue, làm trên nhánh riêng theo TDD rồi mở pull request.
- Việc "đã xong" do **máy kiểm tra** (`scripts/check.sh` và CI), không dựa vào lời Claude tự báo.
- **Người merge.** Không có gì tự động vào `main`.

```
Issue (mục tiêu + tiêu chí nghiệm thu)
  │  gắn nhãn "claude"  hoặc  /task trên máy
  ▼
Claude: nhánh riêng → kế hoạch → TDD → ./scripts/check.sh
  │   ├─ guard.sh chặn lệnh nguy hiểm (force push, push main, rm -rf /, đọc .env…)
  │   └─ verify-on-stop.sh: check đỏ thì chưa được dừng, phải sửa tiếp
  ▼
Pull request
  │
  ▼
CI (check.sh trên máy sạch)  ← cổng thật, required status check
  ▼
Claude review tự động (3 góc nhìn + tự phản biện) → comment vào PR
  ▼
Người review và merge (branch protection)
```

## Bộ kit gồm những gì

| File (trong repo đích) | Vai trò |
|---|---|
| `CLAUDE.md` | Thông tin dự án (bạn điền) và import quy trình |
| `.claude/sdlc/RULES.md` | Nguyên tắc làm việc, quy trình 7 bước, khi nào phải dừng và hỏi |
| `.claude/settings.json` | Quyền hẹp (allow/deny), 2 hook, bật plugin Superpowers |
| `.claude/hooks/guard.sh` | Hook PreToolUse: chặn lệnh phá hoại hoặc không đảo ngược được |
| `.claude/hooks/verify-on-stop.sh` | Hook Stop: có thay đổi chưa kiểm chứng thì chạy `check.sh`, đỏ thì Claude phải sửa (tối đa 3 lần, sau đó cảnh báo bạn) |
| `.claude/commands/task.md` | `/task <số issue hoặc mô tả>`: làm trọn một task theo quy trình |
| `.claude/commands/review-diff.md` | `/review-diff [nhánh gốc]`: review 3 góc nhìn rồi tự phản biện |
| `scripts/check.sh` | **Cổng chất lượng duy nhất**: lint, typecheck, test, build. Tự nhận diện Node, Python, Go, Rust hoặc `make check` |
| `scripts/fix-loop.sh` | Chạy check → đưa lỗi thật cho Claude sửa → chạy lại. Tối đa 3 vòng, dừng nếu một vòng không thay đổi gì |
| `.github/workflows/ci.yml` | CI chạy `check.sh` cho mỗi PR |
| `.github/workflows/claude.yml` | Claude làm việc khi issue được gắn nhãn `claude` hoặc có comment `@claude` |
| `.github/workflows/claude-review.yml` | Claude review khi PR được mở hoặc chuyển sang ready |
| `.github/ISSUE_TEMPLATE/claude-task.yml` | Mẫu issue bắt buộc có tiêu chí nghiệm thu |
| `.github/pull_request_template.md` | Mẫu PR bắt buộc có bằng chứng kiểm chứng |

## Cài vào một repo

Yêu cầu: `git`, `bash`, `python3`; nên có `jq`. Cần [Claude Code](https://code.claude.com) và `gh` (GitHub CLI).

```bash
./install.sh /đường/dẫn/tới/repo-của-bạn
```

- File đã tồn tại và khác kit thì **được giữ nguyên** (thêm `--force` để thay, bản cũ được lưu vào `.sdlc-backup/`).
- Nếu repo đã có `CLAUDE.md`, installer chỉ thêm một dòng import. `.claude/settings.json` được gộp, cấu hình của bạn luôn được ưu tiên.
- Chạy lại nhiều lần vẫn an toàn.

Sau khi cài:

1. Điền phần thông tin dự án trong `CLAUDE.md` (dưới 60 dòng).
2. Chạy `./scripts/check.sh`. Nếu nó báo "no stack detected" hoặc chưa chạy đủ lint/test/build của bạn, hãy thêm target `check:` vào `Makefile` hoặc sửa `scripts/check.sh`.
3. Mở Claude Code tương tác trong repo **một lần** và chấp nhận hộp thoại tin cậy (trust). Nếu không, `claude -p` (mà `fix-loop.sh` dùng) sẽ bỏ qua danh sách quyền `allow`.
4. Commit kit trên một nhánh và mở PR.

### Thiết lập GitHub (một lần cho mỗi repo)

1. Trong Claude Code, chạy `/install-github-app` để cài Claude GitHub App và secret. Để **không tốn thêm tiền**, chọn secret `CLAUDE_CODE_OAUTH_TOKEN` (lấy bằng `claude setup-token`) thay cho `ANTHROPIC_API_KEY`: xem mục [Chạy miễn phí](#chạy-miễn-phí).
2. Tạo nhãn `claude`.
3. Bật **branch protection** cho `main`: bắt buộc qua PR, bắt buộc status check **`check`** của CI, chặn force push. Làm một mình thì để số approval bằng 0, vì GitHub không cho tác giả tự approve PR của mình. Có nhóm thì đặt ít nhất 1.

### Chạy miễn phí

| Thành phần | Miễn phí khi | Ghi chú |
|---|---|---|
| Branch protection | Repo **public** | Repo private trên gói Free không có tính năng này |
| GitHub Actions (CI) | Repo **public**: không giới hạn | Repo private: 2.000 phút/tháng, và phút macOS bị tính gấp 10 lần. Nên chỉ chạy CI trên Ubuntu |
| Claude trên GitHub | Dùng `CLAUDE_CODE_OAUTH_TOKEN` | Tính vào hạn mức gói Claude Pro/Max bạn đang dùng, không tốn thêm tiền. `ANTHROPIC_API_KEY` bị tính tiền theo token |
| Claude Code trên máy | Gói Claude bạn đang có | Không cần gì thêm |

Muốn hoàn toàn không phát sinh chi phí AI, chỉ cần không thêm secret nào. CI và các hook vẫn chạy bình thường; hai workflow Claude sẽ báo lỗi thiếu xác thực, hoặc bạn xoá `claude.yml` và `claude-review.yml` đi.

## Dùng hằng ngày

| Bạn muốn | Làm thế này |
|---|---|
| Làm cùng Claude trên máy | `claude` rồi gõ `/task 42` hoặc `/task sửa lỗi đăng nhập khi email có chữ hoa` |
| Giao việc cho Claude tự làm | Tạo issue bằng mẫu **Task cho Claude**, rồi gắn nhãn `claude`. Claude làm trên nhánh `claude/…` và gửi link tạo PR |
| Nhờ Claude sửa tiếp trên PR | Comment `@claude <yêu cầu>` vào PR |
| Review lại PR sau khi push thêm | Comment `@claude review lại theo .claude/commands/review-diff.md` |
| Check đang đỏ, nhờ Claude sửa đến khi xanh | `./scripts/fix-loop.sh` (đổi số vòng bằng `SDLC_FIX_ROUNDS=5`) |
| Tạm tắt cổng Stop cho một phiên | `SDLC_SKIP_VERIFY=1 claude` |
| Cho phép commit lên `main` một lần (ví dụ commit đầu tiên) | Tự chạy lệnh đó, hoặc mở phiên bằng `SDLC_ALLOW_MAIN=1 claude` |

**Viết issue tốt là yếu tố quyết định.** Claude làm tốt khi có tiêu chí nghiệm thu kiểm chứng được và phạm vi rõ ràng. Task "Lớn" nên được chia thành nhiều issue "Vừa".

## Lộ trình áp dụng

| Giai đoạn | Việc làm |
|---|---|
| Tuần 1 | Cài kit, cấu hình `check.sh`, bật CI và branch protection. Dùng `/task` tương tác. |
| Tuần 2 | Bật `claude-review.yml`: Claude review cả PR do người viết. |
| Tuần 3–4 | Giao các issue nhỏ/vừa có tiêu chí rõ bằng nhãn `claude`. Bạn chỉ review và merge. |
| Sau đó | Theo dõi tỷ lệ PR merge mà không phải sửa tay, rồi mở rộng dần sang task lớn hơn. |

## Giới hạn cần biết

- **`guard.sh` là rào chắn chống nhầm lẫn và prompt injection, không phải sandbox.** Lệnh được viết lách khéo vẫn có thể lọt. Lớp bảo vệ thật nằm ở branch protection, quyền GitHub token, và việc không để secret trong repo. Đôi khi nó chặn nhầm, ví dụ một commit message có chứa chữ `rm -rf /`.
- **Hạn mức**: mỗi lần Claude chạy trên GitHub dùng hạn mức gói Claude của bạn (hoặc tốn tiền nếu dùng API key). Review tự động chỉ chạy khi PR được mở hoặc chuyển sang ready, không chạy theo mỗi lần push.
- `claude.yml` cho Claude quyền ghi vào repo (trên nhánh `claude/…`). Chỉ người có quyền ghi mới kích hoạt được. **Không** bật `allowed_non_write_users`.
- Windows: cần Git Bash hoặc WSL để chạy các hook `.sh`.
- **Không nên đặt repo git trong OneDrive/Dropbox**: đồng bộ thư mục `.git` dễ làm hỏng repo. Hãy đẩy lên GitHub và làm việc ở một thư mục ngoài OneDrive.

## Phát triển bản thân kit

```bash
bash tests/run-all.sh
```

Có 174 kiểm thử cho `guard.sh`, `verify-on-stop.sh`, `check.sh`, `fix-loop.sh`, `install.sh` và cấu hình. CI của repo này (`.github/workflows/test.yml`) chạy thêm `shellcheck` trên Ubuntu và macOS.

Ý tưởng review đa góc nhìn kèm tự phản biện, và vòng sửa lỗi có giới hạn, được tham khảo từ `@ennamjsc/agents-scaffold`. Mã trong kit này được viết mới hoàn toàn: gói kia không có giấy phép mã nguồn mở.
