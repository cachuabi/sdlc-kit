---
description: Review thay đổi so với nhánh gốc theo 3 góc nhìn, rồi tự phản biện từng phát hiện trước khi báo cáo.
argument-hint: "[nhánh gốc, mặc định main]"
---

Review thay đổi của nhánh hiện tại so với nhánh gốc `$ARGUMENTS` (để trống thì dùng `main`). **Không sửa file nào trong lệnh này.**

1. Lấy phạm vi thay đổi: `git diff <gốc>...HEAD`, cộng `git diff` và `git diff --staged` cho phần chưa commit. Nếu `<gốc>` không tồn tại thì thử `origin/<gốc>`. Không lấy được diff thì báo blocker "Không tính được diff", **không** được báo là sạch.
2. Review lần lượt 3 góc nhìn, chỉ trên các dòng đã đổi và code bị chúng ảnh hưởng trực tiếp:
   - **Đúng sai**: bug, trường hợp biên, lỗi bị nuốt, rủi ro bảo mật (injection, lộ secret, thiếu kiểm tra quyền).
   - **Quy ước**: vi phạm `.claude/sdlc/RULES.md` và quy ước code xung quanh đang theo.
   - **Test**: thiếu test, hoặc test vẫn pass khi logic nghiệp vụ sai.
3. **Tự phản biện**: với mỗi phát hiện, đọc lại đúng đoạn code được trích và cố bác bỏ nó (đọc sai logic, đã xử lý ở chỗ khác, không thể xảy ra). Bác được thì bỏ. Không chắc thì giữ lại nhưng ghi "chưa xác nhận".
4. Báo cáo dạng bảng, xếp theo mức độ:

| Mức | File:dòng | Vấn đề | Tình huống lỗi cụ thể | Hướng sửa |
|---|---|---|---|---|

Mức: **blocker** (phải sửa trước khi merge) · **major** (nên sửa) · **minor** · **nit**.
Không có gì đáng báo thì nói rõ "Không tìm thấy vấn đề" và liệt kê những góc đã kiểm tra.
