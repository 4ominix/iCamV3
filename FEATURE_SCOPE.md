# Phạm vi iCamV3 1.3.1

## Có trong source
Ảnh/video cục bộ, PHPicker, preview, loop, bật/tắt, Fit/Fill, mirror, rotation, pan, zoom, reset; bảng điều khiển trong app và floating control SpringBoard; shared config trong jbroot; frame worker và fallback real-camera; diagnostics per-host.

## Không có
Đăng nhập/tài khoản, backend/server, token/heartbeat/lease, HTTP/socket client, OBS/RTMP, network daemon. Không sử dụng binary obfuscated hay UI độc quyền cũ. Color sync và face privacy mask chưa được triển khai lại trong source độc lập này.

## Giao tiếp
File Config.plist trong `jbroot(/var/mobile/Library/iCamV3)`, nguồn filename tương đối, Darwin notification `com.icamv3.config-changed`. CameraStatus.mediaserverd.plist / CameraStatus.cameracaptured.plist ghi counters, không chứa token/media cá nhân.

## Giới hạn chứng cứ
Local tests chỉ kiểm tra source/package contracts. Hành vi camera, sandbox entitlement và injection trên iPhone chưa được kiểm chứng cho release 1.3.1. Giao diện dựa trên ảnh tham chiếu, không khẳng định sao chép đầy đủ UI bản gốc.
