# iCamV3 1.3.1 — camera ảo ngoại tuyến

Source độc lập gồm app điều khiển, camera tweak và bảng điều khiển nổi. Không có đăng nhập, tài khoản, backend, token, server/OBS/RTMP hoặc daemon mạng. Giao diện tối và bảng Camera control được dựng lại từ hình tham chiếu; không phải mã UI gốc của VCNext.

## Chức năng
- PHPicker chọn ảnh/video; sao chép file tạm ngay trong completion handler.
- Lưu nguồn và cấu hình atomically; lỗi nhập/lưu giữ nguyên cấu hình trước đó.
- Video preview và nguồn camera phát lặp khi bật Loop.
- Bật/tắt, Fit/Fill, xoay, lật ngang, zoom 0.25–8x, dịch chuyển.
- Mũi tên, zoom, reset trong app; kéo/chụm trên preview để thay đổi vị trí/zoom.
- Nút nổi có thể kéo trên SpringBoard. Chạm mở Camera control; mũi tên dịch media, ↻ xoay, ⇆ lật, Đặt lại reset transform.
- Nút nổi chỉ hiện khi camera ảo được bật và máy không khóa. Respring sau cài để nạp SpringBoard tweak.
- Chẩn đoán thực tế: số hook đã cài, số lần chép frame, lỗi nguồn/render. Không báo đã hoạt động chỉ vì app lưu thành công.

## Sửa lỗi quyền ghi trên RootHide
App có các entitlement được tài liệu RootHide đề xuất: platform-application, no-sandbox, storage.AppBundles, storage.AppDataContainers.
App và camera host dùng `jbroot(@"/var/mobile/Library/iCamV3")` cho Foundation. Script chạy trong bootstrap dùng `/var/mobile/Library/iCamV3` (đường dẫn logic trong jbroot), không dùng `/var/jb`. Script tạo thư mục mobile:mobile 0775; media/plist 0644. Filename media được lưu tương đối để không phụ thuộc tên jbroot ngẫu nhiên.

Tài liệu: https://github.com/roothide/Developer/blob/main/entitlements.md và https://github.com/roothide/Developer/blob/main/roothide.md

## Kiến trúc
- `iCamV3App`: chọn media, preview, cấu hình, chẩn đoán.
- `iCamV3.dylib`: chỉ nạp vào mediaserverd/cameracaptured. Hook BWNodeOutput và bốn camera sink; retry khi class nạp muộn, kiểm tra số argument/return ABI.
- `iCamV3Controls.dylib`: chỉ nạp SpringBoard; không decode video/can thiệp camera.
- Decode/render chạy trên worker serial, cadence 30Hz, video theo presentation timestamps.
- Cache tối đa ba kích thước/format. Prewarm 1080×1440 và 1584×1188 NV12 full-range từ trace cung cấp.
- Callback camera không dispatch_sync/decode/render; try-lock và chép cache cùng format/kích thước.
- Render vào scratch trước; kiểm tra toàn bộ plane trước khi chép vào camera thật. Thiếu media, format lạ, chưa có cache, decode/render lỗi hoặc EOF không loop thì giữ frame thật.
- Preview app dùng viewport 3:4; camera host dùng kích thước buffer thực nên crop có thể khác ở camera landscape.

## Build GitHub
Upload toàn bộ nội dung thư mục này, gồm `.github`, `.gitignore`, `.gitattributes`. Không upload `analysis`, backup, Theos tải về, `.theos`, packages hoặc ZIP cũ ở thư mục cha.
Workflow build trên macOS, chạy structural tests và native geometry tests, build arm64 + arm64e, kiểm tra app/tweak trong DEB và entitlement **trên executable đã ký** rồi upload artifact `iCamV3-RootHide-DEB`.

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

Thư mục này chưa chứa DEB mới. Không dùng lại bản 1.2.x để thử bản sửa.

## Cài và thử trên máy
1. Cài DEB 1.3.1 từ artifact qua Sileo. Nếu dpkg đang có reinstreq, xử lý gói hỏng trước; đừng xóa database dpkg.
2. Respring bằng công cụ jailbreak. Mở iCamV3, chọn ảnh, kiểm tra không còn lỗi ghi thư mục.
3. Bật camera ảo, mở Camera, quay lại app xem trạng thái host. `hooks=0` chỉ ra class/injection chưa sẵn sàng; `frame=0` nghĩa là chưa có lần chép frame thành công.
4. Không có status sau khi mở Camera: kiểm tra dylib được RootHide nạp vào camera host. Có status `source-unreadable`: kiểm tra quyền/path; `render-error`: giữ lại thông báo để chẩn đoán.
5. Camera thực tế có thể đổi đường private API giữa phiên bản iOS/model. Hai host/hook đã quan sát trước đây không chứng minh mọi ứng dụng camera hoặc mọi thiết bị đều được hỗ trợ.

## Test bắt buộc trên thiết bị
- Tắt: preview/chụp/quay thật. Bật nhưng nguồn mất: frame thật, host không restart/crash.
- Ảnh: chọn ảnh HEIC/JPEG, preview và ảnh chụp được thay. Thử camera trước/sau, portrait/landscape.
- Video: theo thời gian, loop, không loop trở về frame thật khi hết; quay và mở lại nguồn.
- Mũi tên/zoom/lật/xoay/Fit/Fill: kiểm tra cả app, live camera, ảnh chụp và bản ghi.
- Tắt app điều khiển: media vẫn hoạt động; bảng nổi cập nhật cùng cấu hình.
- Respring/re-jailbreak: paths vẫn đúng, app xuất hiện, hosts có status mới.
- Lock/unlock: bảng nổi ẩn ở màn khóa; touch vùng ngoài bảng đi tới app bên dưới.

## Mức kiểm chứng
`tests/test_source.py` và `scripts/validate.ps1` là kiểm tra cấu trúc, không phải iOS compiler/runtime test. `tests/geometry.c` được compile/chạy bởi GitHub Actions. Cần build CI và test iPhone mới xác nhận hành vi.

## Gỡ
Gỡ `com.icamv3.app` bằng Sileo rồi Respring. Không tự xóa dữ liệu cá nhân/nguồn media trong script gỡ. Các package cũ được quản lý bởi Conflicts/Replaces của dpkg; preinst không xóa tay file của package khác.
