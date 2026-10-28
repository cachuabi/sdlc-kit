# Quy trình phát triển (SDLC kit)

Áp dụng cho mọi agent và mọi task trong repo này, trừ khi người dùng nói khác trong cuộc hội thoại.

## Nguyên tắc làm việc

1. **Hiểu trước, code sau.** Nêu rõ giả định. Yêu cầu mơ hồ thì hỏi, đừng đoán.
2. **Tối thiểu.** Chỉ viết code mà task cần. Không thêm tính năng, không trừu tượng hoá "để dành".
3. **Sửa đúng chỗ.** Chỉ chạm vào file task cần. Không tiện tay refactor, đổi format hay "cải thiện" code bên cạnh.
4. **Đọc trước khi viết.** Đọc code gọi tới và code xung quanh, rồi theo đúng quy ước sẵn có của repo.
5. **Test chứng minh ý định.** Test phải fail nếu logic nghiệp vụ sai. Không bao giờ xoá, skip hay nới lỏng test để cho qua.
6. **Báo đúng sự thật.** Không nói "xong" khi còn bước bị bỏ qua. Không nói "test pass" nếu chưa thấy exit code 0.
7. **Thấy mâu thuẫn thì nêu ra**, đừng tự trộn hai cách làm.

## Quy trình cho mỗi task

| Bước | Việc phải làm | Đầu ra |
|---|---|---|
| 1. Hiểu | Đọc issue hoặc yêu cầu. Viết lại **tiêu chí nghiệm thu** dạng checklist. Thiếu tiêu chí thì dừng và hỏi. | Checklist tiêu chí |
| 2. Nhánh | `git switch -c <type>/<mô-tả-ngắn>` (type: feat, fix, refactor, docs, test, chore). Không làm trên `main`. | Nhánh mới |
| 3. Kế hoạch | Task từ 3 bước trở lên: viết kế hoạch kèm cách kiểm chứng từng bước. Có Superpowers thì dùng `superpowers:writing-plans`. | Kế hoạch |
| 4. Làm theo TDD | Viết test (đỏ) → code tối thiểu (xanh) → dọn dẹp. Có Superpowers thì dùng `superpowers:test-driven-development`. | Code + test |
| 5. Kiểm chứng | Chạy `./scripts/check.sh`. **Chỉ exit code 0 mới là bằng chứng.** Đỏ thì sửa nguyên nhân gốc. | Output check.sh |
| 6. Tự review | Chạy `/review-diff` trên thay đổi của mình và sửa các lỗi blocker/major. | Danh sách đã xử lý |
| 7. Hoàn tất | Commit theo Conventional Commits (`feat: …`). Soạn mô tả PR theo `.github/pull_request_template.md`. **Không merge.** | Commit + mô tả PR |

Mức độ task quyết định số bước bắt buộc:

| Mức | Ví dụ | Bước bắt buộc |
|---|---|---|
| Nhỏ | Sửa typo, đổi một giá trị config | 1, 2, 5, 7 |
| Vừa | Sửa bug một module, thêm một endpoint | 1, 2, 4, 5, 6, 7 |
| Lớn | Tính năng đi qua nhiều module | Tất cả các bước |

Bước 5 **không bao giờ được bỏ qua**.

## Cổng chặn tự động (không được lách)

- `PreToolUse` hook (`.claude/hooks/guard.sh`) chặn: force push, push hoặc commit thẳng lên `main`, `--no-verify`, `reset --hard`, xoá đệ quy ngoài dự án, `curl | sh`, `sudo`, publish, `gh pr merge`, đọc `.env` hay khoá SSH.
- `Stop` hook (`.claude/hooks/verify-on-stop.sh`) chạy `./scripts/check.sh` khi có thay đổi chưa kiểm chứng. Đỏ thì phải sửa tiếp.
- Bị chặn thì **không tìm cách khác để đạt cùng mục đích**. Dừng lại và báo người dùng.

## Khi nào phải dừng và hỏi người

- Cần hành động không đảo ngược được hoặc ra bên ngoài: push, mở hay merge PR, xoá dữ liệu, gửi tin nhắn, đổi hạ tầng.
- Phạm vi phình ra ngoài task: thêm package mới, dịch vụ ngoài, schema DB, file ngoài phạm vi.
- Sửa 2 vòng liên tiếp mà vẫn đỏ với cùng một lỗi.
- Gặp trạng thái lạ: file, nhánh hay lock không rõ nguồn gốc. Điều tra, không xoá.

## Khi chạy không có người (GitHub Actions, `claude -p`)

- Không có ai để hỏi. Nếu yêu cầu mơ hồ, viết câu hỏi vào comment của issue hoặc PR rồi **dừng**, đừng đoán.
- Không bao giờ merge, release hay xoá nhánh. Người duyệt PR là cổng cuối cùng.
- Ghi rõ trong mô tả PR: đã kiểm chứng gì, chưa kiểm chứng gì, rủi ro còn lại.
