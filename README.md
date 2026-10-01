# FortiGate IPsec VPN trên Linux (Docker)

Kết nối VPN FortiGate loại **IPsec + PSK + XAuth + OTP qua email** bằng một container.
Không cần cài FortiClient hay strongSwan trên máy: image tự build strongSwan 6.0.5 kèm
[bản vá OTP email](src/xauth-email-token.patch).

## Dùng nhanh

1. **Tạo cấu hình** (copy từ file mẫu rồi điền thông tin do admin VPN cung cấp):
   ```bash
   cp config/ipsec.conf.example    config/ipsec.conf
   cp config/ipsec.secrets.example config/ipsec.secrets
   chmod 600 config/ipsec.secrets
   ```
   - `ipsec.conf`: IP gateway, username, tên profile (`conn ...`).
   - `ipsec.secrets`: PSK và password của từng user.
2. **Khai báo profile** trong `docker-compose.yml`: mỗi profile là một service, `command` là tên `conn`.
3. **Dừng strongSwan trên máy** nếu đang chạy, tránh tranh port 500/4500: `sudo ipsec stop`
4. **Kết nối**:
   ```bash
   docker compose run --rm milize     # hoặc: docker compose run --rm anh
   ```
   Khi hiện `OTP code (from email):`, mở email lấy mã và nhập **trong khoảng 60 giây**.
   Thấy `✓ connected` là xong. **Ctrl+C để ngắt.**

Lần đầu `run` sẽ build image (vài phút).

## Kiểm tra đã đi qua VPN chưa

```bash
curl https://ifconfig.me     # phải ra IP của gateway, không phải IP nhà mạng
```
(Chỉ đúng với full tunnel `rightsubnet=0.0.0.0/0`. Split tunnel thì thử truy cập tài nguyên nội bộ.)

## Cấu trúc

| Đường dẫn | Vai trò |
|---|---|
| `config/` | Cấu hình và secret của bạn, được mount vào container (không nằm trong image) |
| `docker-compose.yml` | Mỗi service = một profile VPN, chạy một lần một profile |
| `vpn.sh` | Entrypoint: chạy charon, hỏi OTP, giữ kết nối |
| `Dockerfile` | Build strongSwan + patch, image cuối ~110MB |
| `src/` | File patch OTP (từ repo `north3rnlights/strongswan-fortigate-email-2fa`) |
| `backup/` | Các script cũ chạy trực tiếp trên máy, để tham khảo |

## Thêm profile mới

1. Thêm một khối `conn <tên>` vào `config/ipsec.conf` và một dòng `<user> : XAUTH "..."` vào `config/ipsec.secrets`.
2. Thêm service vào `docker-compose.yml`:
   ```yaml
   congty-moi:
     <<: *vpn
     profiles: ["congty-moi"]
     command: ["<tên conn>"]
   ```
3. Chạy `docker compose run --rm congty-moi`.

## Gặp lỗi

| Hiện tượng | Nguyên nhân thường gặp |
|---|---|
| `failed before OTP` | Sai PSK, username/password, hoặc thông số mã hóa (`ike=`/`esp=`) không khớp gateway. Xem 20 dòng log in ra. |
| `no OTP challenge` | Gateway không gửi vòng OTP: sai profile hoặc tài khoản không bật 2FA email. |
| Nhập OTP xong thất bại | Gõ chậm quá ~60 giây, mã bị bỏ qua. Chạy lại để nhận mã mới. |
| Kết nối được nhưng IP vẫn là IP nhà mạng | Xem lại `vpn.sh` (rule NAT bypass) và subnet bridge Docker có trùng IP ảo VPN. |
| Báo cổng 500/4500 bị chiếm | `sudo ipsec stop` trên máy host. |

## Lưu ý

- Container chạy `network_mode: host` với `NET_ADMIN` nên VPN áp dụng cho **cả máy**.
- Mỗi lần kết nối tốn một email OTP, không chạy lặp khi chưa cần.
- Không commit `config/ipsec.secrets`.
