---
description: Làm một task từ đầu đến cuối theo quy trình SDLC (issue → nhánh → TDD → kiểm chứng → review → commit).
argument-hint: <số issue hoặc mô tả task>
---

Thực hiện task sau theo đúng `.claude/sdlc/RULES.md`: $ARGUMENTS

1. **Hiểu**: nếu đầu vào là số issue, đọc nó bằng `gh issue view <số> --comments`. Viết lại tiêu chí nghiệm thu thành checklist và xếp task vào mức Nhỏ, Vừa hoặc Lớn. Thiếu tiêu chí thì dừng và hỏi.
2. **Nhánh**: nếu đang ở `main`/`master`, tạo nhánh `<type>/<mô-tả-ngắn>`.
3. **Kế hoạch** (mức Vừa và Lớn): liệt kê các bước, mỗi bước kèm cách kiểm chứng.
4. **TDD**: viết test đỏ trước, rồi code tối thiểu cho xanh.
5. **Kiểm chứng**: chạy `./scripts/check.sh` và dán dòng tóm tắt PASSED/FAILED. Đỏ thì sửa nguyên nhân gốc.
6. **Tự review**: làm theo `/review-diff` và xử lý các lỗi blocker/major.
7. **Commit** theo Conventional Commits. Soạn mô tả PR theo `.github/pull_request_template.md`.

Không push, không mở PR và không merge nếu người dùng chưa đồng ý trong cuộc hội thoại này.
Cuối cùng báo cáo: tiêu chí nào đạt (kèm bằng chứng), việc gì chưa làm, rủi ro còn lại.
