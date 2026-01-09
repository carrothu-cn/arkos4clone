#!/usr/bin/env bash
set -euo pipefail

# ============================================
# ArkOS4Clone OTA 升级包制作脚本（chunk 流式安装 + modules 复制 + uboot 刷写）
#
# 输出文件：
#   ./update.tar   （最终放到设备的 /roms/update.tar）
#
# update.tar 内部结构：
#   VERSION
#   install.sh         # 设备端执行脚本（支持从 update.tar 流式抽取 chunks/ 与 uboot/）
#   CHUNKS             # chunk 清单（顺序执行）
#   chunks/
#     00_boot.tar
#     10_root_usr_etc.tar
#     20_root_opt.tar
#     30_root_home.tar
#     40_root_misc.tar
#   uboot/
#     idbloader.img
#     uboot.img
#     trust.img
#
# 目标：
# - 设备端不整包解压到 /home/ark（只解最小文件），其余均从 update.tar 流式抽取并解包/刷写
# ============================================

# 生成版本信息
UPDATE_DATE="$(TZ=Asia/Shanghai date +%m%d%Y)"
MODDER="kk&lcdyk"
VERSION="ArkOS4Clone-${UPDATE_DATE}-${MODDER}"

# 工作目录与临时构建目录
WORKDIR="$(pwd)"
STAGE="/tmp/_ota_stage"
PAYLOAD_BOOT="${STAGE}/payload/boot"
PAYLOAD_ROOT="${STAGE}/payload/root"
OUT_TAR="${WORKDIR}/update.tar"

# boot 分区（FAT32）专用 rsync 参数
RSYNC_BOOT_OPTS="-rltD --no-owner --no-group --no-perms --omit-dir-times"

# 清理旧的构建目录
rm -rf "$STAGE"
mkdir -p "$PAYLOAD_BOOT" "$PAYLOAD_ROOT"

echo "== 构建 payload/boot =="

# consoles -> /boot/consoles（排除 consoles/files）
mkdir -p "$PAYLOAD_BOOT/consoles"
rsync $RSYNC_BOOT_OPTS --exclude='files' ./consoles/ "$PAYLOAD_BOOT/consoles/"

# clone.sh 在 OTA 中必须直接生成为 /boot/firstboot.sh
cp -f ./sh/clone.sh "$PAYLOAD_BOOT/firstboot.sh"

# 其他 boot 工具保持原文件名
cp -f ./dtb_selector_macos_intel \
      ./dtb_selector_win32.exe \
      ./dtb_selector_macos_apple \
      ./sh/expandtoexfat.sh \
      "$PAYLOAD_BOOT/"

# DTB 选择器提示标记文件
touch "$PAYLOAD_BOOT/USE_DTB_SELECT_TO_SELECT_DEVICE" 2>/dev/null || true

echo "== 构建 payload/root =="

echo "== 注入设备怪癖 =="
mkdir -p "$PAYLOAD_ROOT/home/ark/.quirks"
cp -r ./consoles/files/* "$PAYLOAD_ROOT/home/ark/.quirks/"

echo "== 注入 Clone 配置与工具 =="
mkdir -p "$PAYLOAD_ROOT/opt/system/Clone" \
         "$PAYLOAD_ROOT/usr/bin" \
         "$PAYLOAD_ROOT/usr/local/bin"
cp -f ./sh/joyled.sh "$PAYLOAD_ROOT/opt/system/Clone/"
cp -f ./sh/sdljoytest.sh "$PAYLOAD_ROOT/opt/system/Clone/"
cp -f ./bin/mcu_led ./bin/ws2812 "$PAYLOAD_ROOT/usr/bin/"
cp -f ./bin/sdljoymap ./bin/sdljoytest "$PAYLOAD_ROOT/usr/local/bin/"

echo "== 注入 rk915 驱动与固件 =="
mkdir -p "$PAYLOAD_ROOT/usr/lib/firmware" \
         "$PAYLOAD_ROOT/usr/lib/modules/4.4.189/kernel/drivers/net/wireless/mediatek" \
         "$PAYLOAD_ROOT/usr/lib/modules/4.4.189/kernel/drivers/net/wireless/rockchip_wlan/rk915"
cp -f ./bin/mt7610u_sta.ko \
      "$PAYLOAD_ROOT/usr/lib/modules/4.4.189/kernel/drivers/net/wireless/mediatek/" 2>/dev/null || true
cp -f ./bin/rk915_*.bin "$PAYLOAD_ROOT/usr/lib/firmware/" 2>/dev/null || true
cp -f ./bin/rk915.ko \
      "$PAYLOAD_ROOT/usr/lib/modules/4.4.189/kernel/drivers/net/wireless/rockchip_wlan/rk915/" 2>/dev/null || true

echo "== 注入 351Files 资源 =="
mkdir -p "$PAYLOAD_ROOT/opt/351Files/res"
cp -r ./res/* "$PAYLOAD_ROOT/opt/351Files/res/" 2>/dev/null || true

echo "== 注入启动脚本（replace_file/*.sh） =="
mkdir -p "$PAYLOAD_ROOT/usr/local/bin"
cp -f ./replace_file/*.sh "$PAYLOAD_ROOT/usr/local/bin/" 2>/dev/null || true

echo "== 注入 adc-key 服务 =="
mkdir -p "$PAYLOAD_ROOT/etc/systemd/system"
cp -f ./bin/adc-key/adckeys.py "$PAYLOAD_ROOT/usr/local/bin/"
cp -f ./bin/adc-key/adckeys.sh "$PAYLOAD_ROOT/usr/local/bin/"
cp -f ./bin/adc-key/adckeys.service "$PAYLOAD_ROOT/etc/systemd/system/"

echo "== 注入核心与 EmulationStation 文件 =="
mkdir -p "$PAYLOAD_ROOT/home/ark/.config/retroarch/cores" \
         "$PAYLOAD_ROOT/home/ark/.config/retroarch32/cores" \
         "$PAYLOAD_ROOT/etc/emulationstation" \
         "$PAYLOAD_ROOT/usr/bin/emulationstation/resources/locale/zh-CN"
cp -f ./mod_so/64/* "$PAYLOAD_ROOT/home/ark/.config/retroarch/cores/" 2>/dev/null || true
cp -f ./mod_so/32/* "$PAYLOAD_ROOT/home/ark/.config/retroarch32/cores/" 2>/dev/null || true
cp -f ./replace_file/es_systems.cfg "$PAYLOAD_ROOT/etc/emulationstation/"
cp -f ./replace_file/es_systems.cfg.dual "$PAYLOAD_ROOT/etc/emulationstation/"
cp -f ./replace_file/emulationstation2.po \
      "$PAYLOAD_ROOT/usr/bin/emulationstation/resources/locale/zh-CN/" 2>/dev/null || true

# 注意：es_input.cfg 的删除在 install.sh 中完成
mkdir -p "$PAYLOAD_ROOT/usr/bin/emulationstation"
cp -r ./replace_file/emulationstation \
      "$PAYLOAD_ROOT/usr/bin/emulationstation/emulationstation" 2>/dev/null || true

echo "== 注入 drastic =="
mkdir -p "$PAYLOAD_ROOT/opt/drastic"
cp -a ./replace_file/drastic/. "$PAYLOAD_ROOT/opt/drastic/" 2>/dev/null || true
rm -rf "$PAYLOAD_ROOT/opt/drastic/patch" 2>/dev/null || true

# NDS Overlay
mkdir -p "$PAYLOAD_ROOT/opt/system/Advanced/NDS Overlays"
cp -a ./replace_file/nds_sh/* \
      "$PAYLOAD_ROOT/opt/system/Advanced/NDS Overlays/" 2>/dev/null || true

echo "== 注入 retrorun =="
mkdir -p "$PAYLOAD_ROOT/usr/local/bin"
cp -r ./replace_file/retrorun/retrorun32 "$PAYLOAD_ROOT/usr/local/bin/" 2>/dev/null || true
cp -r ./replace_file/retrorun/retrorun "$PAYLOAD_ROOT/usr/local/bin/" 2>/dev/null || true

echo "== 注入 pymo =="
cp -r ./replace_file/pymo/cpymo "$PAYLOAD_ROOT/usr/local/bin/" 2>/dev/null || true
cp -r ./replace_file/pymo/pymo.sh "$PAYLOAD_ROOT/usr/local/bin/" 2>/dev/null || true
mkdir -p "$PAYLOAD_ROOT/tempthemes/es-theme-nes-box"
cp -r ./replace_file/pymo/pymo \
      "$PAYLOAD_ROOT/tempthemes/es-theme-nes-box/" 2>/dev/null || true

echo "== 注入 ogage =="
cp -r ./replace_file/ogage "$PAYLOAD_ROOT/usr/local/bin/" 2>/dev/null || true
cp -r ./replace_file/ogage "$PAYLOAD_ROOT/home/ark/.quirks/" 2>/dev/null || true

echo "== 注入 services / tools =="
mkdir -p "$PAYLOAD_ROOT/etc/systemd/system" \
         "$PAYLOAD_ROOT/opt/system/Advanced" \
         "$PAYLOAD_ROOT/usr/local/bin"
cp -r ./replace_file/services/351mp.service \
      "$PAYLOAD_ROOT/etc/systemd/system/" 2>/dev/null || true
cp -r "./replace_file/tools/Enable Quick Mode.sh" \
      "$PAYLOAD_ROOT/opt/system/Advanced/" 2>/dev/null || true
cp -r "./replace_file/tools/Switch to SD2 for Roms.sh" \
      "$PAYLOAD_ROOT/opt/system/Advanced/" 2>/dev/null || true
cp -r "./replace_file/tools/Enable Quick Mode.sh" \
      "$PAYLOAD_ROOT/usr/local/bin/" 2>/dev/null || true
cp -r "./replace_file/tools/Disable Quick Mode.sh" \
      "$PAYLOAD_ROOT/usr/local/bin/" 2>/dev/null || true
cp -r "./replace_file/tools/Switch to main SD for Roms.sh" \
      "$PAYLOAD_ROOT/usr/local/bin/" 2>/dev/null || true
cp -r "./replace_file/tools/Switch to SD2 for Roms.sh" \
      "$PAYLOAD_ROOT/usr/local/bin/" 2>/dev/null || true

# ========= 新增：复制 replace_file/modules -> /usr/lib/modules =========
echo "== 注入 modules（replace_file/modules -> /usr/lib/modules） =="
if [[ -d "./replace_file/modules" ]]; then
  mkdir -p "$PAYLOAD_ROOT/usr/lib/modules"
  cp -a ./replace_file/modules/. "$PAYLOAD_ROOT/usr/lib/modules/" 2>/dev/null || true
fi

# ========= ROMS.TAR 被明确排除（OTA 不处理用户数据） =========
echo "== 跳过 roms.tar（设计如此） =="

# -----------------------------
# 写入 VERSION 与 install.sh
# -----------------------------
echo "== 写入 VERSION 与 install.sh =="

cat > "$STAGE/VERSION" <<EOF
$VERSION
EOF

cat > "$STAGE/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

BASE="$(cd "$(dirname "$0")" && pwd)"
PAYLOAD="$BASE/payload"

# 外层 update.tar 的路径（由 maybe_apply_ota_update 传入）
OTA_TAR_PATH="${OTA_TAR_PATH:-}"
CHUNKS_FILE="$BASE/CHUNKS"

# 兼容外层脚本的日志文件（若外层没传，就用默认）
LOG_FILE="${LOG_FILE:-/boot/clone_log.txt}"

have_systemctl() { command -v systemctl >/dev/null 2>&1; }

svc_stop_disable() {
  local svc="$1"
  have_systemctl || return 0
  systemctl stop "$svc" 2>/dev/null || true
  systemctl disable "$svc" 2>/dev/null || true
  systemctl reset-failed "$svc" 2>/dev/null || true
}

# 先停掉可能冲突/要替换的服务（存在才动）
for s in adckeys.service batt_led.service ddtbcheck.service 351mp.service mpv.service; do
  if [[ -e "/etc/systemd/system/$s" || -e "/lib/systemd/system/$s" ]]; then
    svc_stop_disable "$s"
  fi
done

# 查找 boot 分区挂载点
BOOT_MP="$(findmnt -n -o TARGET /dev/mmcblk0p1 2>/dev/null || true)"
[[ -z "$BOOT_MP" ]] && BOOT_MP="/boot"

# 重新挂载 boot 为可写（失败不致命）
mount -o remount,rw "$BOOT_MP" 2>/dev/null || true

apply_chunk_stream() {
  local target="$1"   # boot | root
  local member="$2"   # chunks/xx.tar
  local OTA_TMP="/home/ark/.ota"
  local dest="/"
  [[ "$target" == "boot" ]] && dest="$BOOT_MP"
  echo "[OTA] apply $target <- $member (via $OTA_TMP) -> $dest"
  # 确保临时目录存在且干净
  rm -rf "$OTA_TMP" 2>/dev/null || true
  mkdir -p "$OTA_TMP"
  # 1流式解包到 /home/ark/.ota
  tar -xO -f "$OTA_TAR_PATH" "$member" | tar -xf - -C "$OTA_TMP"
  # 2rsync 覆盖到目标（关键：不改已有属主）
  if [[ "$target" == "boot" ]]; then
    rsync -rltD --omit-dir-times --no-owner --no-group --no-perms \
      "$OTA_TMP/" "$dest/"
  else
    rsync -a --no-owner --no-group \
      "$OTA_TMP/" "$dest/"
  fi
  # 3清理临时目录
  rm -rf "$OTA_TMP"
}


apply_legacy_rsync() {
  echo "[OTA] legacy mode: rsync payload"
  echo "[OTA] copy boot -> $BOOT_MP"
  if [[ -d "$PAYLOAD/boot" ]]; then
    rsync -rltD --omit-dir-times --no-owner --no-group --no-perms \
      "$PAYLOAD/boot/" "$BOOT_MP/"
  fi

  echo "[OTA] copy root -> /"
  if [[ -d "$PAYLOAD/root" ]]; then
    rsync -aH "$PAYLOAD/root/" "/"
  fi
}

# ====== 应用更新（优先 chunks 流式模式） ======
if [[ -n "$OTA_TAR_PATH" && -f "$OTA_TAR_PATH" && -f "$CHUNKS_FILE" ]]; then
  while read -r t m; do
    [[ -z "${t:-}" || -z "${m:-}" ]] && continue
    apply_chunk_stream "$t" "$m"
    sync || true
  done < "$CHUNKS_FILE"
else
  apply_legacy_rsync
fi

# ========= 新增：刷写 uboot（从外层 update.tar 流式读入，避免落盘） =========
dd_from_tar() {
  local member="$1"
  local seek="$2"

  # member 必须存在才刷写
  if ! tar -tf "$OTA_TAR_PATH" "$member" >/dev/null 2>&1; then
    echo "[OTA] uboot member not found, skip: $member"
    return 0
  fi

  echo "[OTA] flashing: $member (seek=$seek)"
  # 按你给的写法：dd if=xxx of=/dev/mmcblk0 conv=notrunc bs=512 seek=...
  # 这里 if= 用的是 stdin（tar -xO 输出），语义等价于 if=member
  # dd 输出进 LOG_FILE（同时也会被外层 tee 收到）
  tar -xO -f "$OTA_TAR_PATH" "$member" | dd of=/dev/mmcblk0 conv=notrunc bs=512 seek="$seek" 2>&1 | tee -a "$LOG_FILE"
}

# 仅当 /dev/mmcblk0 存在时执行
if [[ -b "/dev/mmcblk0" && -n "$OTA_TAR_PATH" && -f "$OTA_TAR_PATH" ]]; then
  dd_from_tar "uboot/idbloader.img" 64
  dd_from_tar "uboot/uboot.img" 16384
  dd_from_tar "uboot/trust.img" 24576
  sync || true
fi

# plymouth title: ArkOS4Clone (MMDDYYYY)(MODDER)
PLYMOUTH_THEME="/usr/share/plymouth/themes/text.plymouth"
if [[ -f "$BASE/VERSION" && -f "$PLYMOUTH_THEME" ]]; then
  VER_RAW="$(cat "$BASE/VERSION")"
  UPDATE_DATE="$(echo "$VER_RAW" | cut -d- -f2)"
  MODDER="$(echo "$VER_RAW" | cut -d- -f3-)"
  sed -i "/^title=/c\title=ArkOS4Clone (${UPDATE_DATE})(${MODDER})" "$PLYMOUTH_THEME" 2>/dev/null || true
fi

# ===== 旧脚本里存在的“删服务文件”的动作：也搬进来（存在才删，且已 stop/disable）=====
rm -f /etc/systemd/system/batt_led.service 2>/dev/null || true
rm -f /etc/systemd/system/ddtbcheck.service 2>/dev/null || true

# 修正属主与权限（保持与你原脚本一致）
chown -R 1002:1002 /home/ark/.quirks 2>/dev/null || true
chown -R 1002:1002 /opt/system/Clone 2>/dev/null || true
chmod -R 755 /opt/system/Clone 2>/dev/null || true

chmod 755 /usr/bin/mcu_led /usr/bin/ws2812 2>/dev/null || true
chmod 755 /usr/local/bin/sdljoytest /usr/local/bin/sdljoymap 2>/dev/null || true
chown 1002:1002 /usr/bin/mcu_led /usr/bin/ws2812 \
                /usr/local/bin/sdljoytest /usr/local/bin/sdljoymap 2>/dev/null || true

# rk915 驱动 / 固件权限（尽力而为）
chmod 755 /usr/lib/modules/4.4.189/kernel/drivers/net/wireless/rockchip_wlan/rk915/rk915.ko 2>/dev/null || true
chmod 644 /usr/lib/firmware/rk915_*.bin 2>/dev/null || true

# 351Files 重命名（只能在设备端完成）
if [[ -e "/opt/351Files/351Files" ]]; then
  mv "/opt/351Files/351Files" "/opt/351Files/351Files.old" 2>/dev/null || true
fi
chown -R 1002:1002 /opt/351Files 2>/dev/null || true
chmod -R 755 /opt/351Files 2>/dev/null || true

# EmulationStation：移除旧的输入配置
rm -f /etc/emulationstation/es_input.cfg 2>/dev/null || true

# 移除随机 logo
sed -i '/imageshift\.sh/d' /var/spool/cron/crontabs/root 2>/dev/null || true
rm -f /home/ark/.config/imageshift.sh 2>/dev/null || true

# 临时修复
chmod 777 /usr/local/bin/mediaplayer.sh 2>/dev/null || true

# adc-key（路径修正为 /usr/local/bin）
chmod 777 /usr/local/bin/adckeys.py 2>/dev/null || true
chmod 777 /usr/local/bin/adckeys.sh 2>/dev/null || true
chmod 644 /etc/systemd/system/adckeys.service 2>/dev/null || true

# systemd 服务处理
if have_systemctl; then
  systemctl daemon-reload 2>/dev/null || true
  systemctl enable adckeys.service 2>/dev/null || true
  systemctl restart adckeys.service 2>/dev/null || true
fi

# boot 分区清理
rm -rf "$BOOT_MP/BMPs" "$BOOT_MP/ScreenFiles" 2>/dev/null || true
rm -f  "$BOOT_MP/boot.ini" "$BOOT_MP"/*.dtb "$BOOT_MP"/*.orig "$BOOT_MP"/*.tony \
      "$BOOT_MP/Image" "$BOOT_MP"/*.bmp "$BOOT_MP/WHERE_ARE_MY_ROMS.txt" 2>/dev/null || true
rm -f  "$BOOT_MP/DTB Change Tool.exe" 2>/dev/null || true

# 移除不再需要的系统文件
rm -rf /opt/system/DeviceType 2>/dev/null || true
rm -rf "/opt/system/Change LED to Red.sh" 2>/dev/null || true
rm -rf "/opt/system/Advanced/Change Ports SDL.sh" 2>/dev/null || true
find /opt/system/Advanced -name 'Restore*.sh' ! -name 'Restore ArkOS Settings.sh' -exec rm -f {} + 2>/dev/null || true
rm -rf "/opt/system/Advanced/Screen - Switch to Original Screen Timings.sh" 2>/dev/null || true
rm -rf "/opt/system/Advanced/Reset EmulationStation Controls.sh" 2>/dev/null || true
rm -rf "/opt/system/Advanced/Fix Global Hotkeys.sh" 2>/dev/null || true

sync
echo "[OTA] SUCCESS"
EOF
chmod +x "$STAGE/install.sh"

# -----------------------------
# 新增：把 uboot 三件套打进 update.tar（不落 payload，直接放 uboot/）
# -----------------------------
echo "== 打包 uboot 镜像（uboot/*.img） =="
mkdir -p "$STAGE/uboot"
cp -f ./uboot/idbloader.img "$STAGE/uboot/" 2>/dev/null || true
cp -f ./uboot/uboot.img     "$STAGE/uboot/" 2>/dev/null || true
cp -f ./uboot/trust.img     "$STAGE/uboot/" 2>/dev/null || true

# -----------------------------
# 生成 chunks + CHUNKS 清单（分包流式）
# -----------------------------
echo "== 生成 chunks（分包） =="

CHUNK_DIR="$STAGE/chunks"
rm -rf "$CHUNK_DIR" 2>/dev/null || true
mkdir -p "$CHUNK_DIR"
ls -lh "$CHUNK_DIR" || true

# boot chunk
tar --numeric-owner --owner=0 --group=0 \
  -C "$PAYLOAD_BOOT" -cf "$CHUNK_DIR/00_boot.tar" .

# root chunks（按目录拆，降低单次解包峰值）
tar --numeric-owner --owner=0 --group=0 \
  -C "$PAYLOAD_ROOT" -cf "$CHUNK_DIR/10_root_usr_etc.tar" \
  ./usr ./etc 2>/dev/null || true

tar --numeric-owner --owner=0 --group=0 \
  -C "$PAYLOAD_ROOT" -cf "$CHUNK_DIR/20_root_opt.tar" \
  ./opt 2>/dev/null || true

tar --numeric-owner --owner=0 --group=0 \
  -C "$PAYLOAD_ROOT" -cf "$CHUNK_DIR/30_root_home.tar" \
  ./home 2>/dev/null || true

tar --numeric-owner --owner=0 --group=0 \
  -C "$PAYLOAD_ROOT" -cf "$CHUNK_DIR/40_root_misc.tar" \
  ./var ./lib ./sbin ./bin ./run ./root ./media ./mnt ./tmp 2>/dev/null || true

rm -rf "$STAGE/CHUNKS" 2>/dev/null || true
cat > "$STAGE/CHUNKS" <<'EOF'
boot chunks/00_boot.tar
root chunks/10_root_usr_etc.tar
root chunks/20_root_opt.tar
root chunks/30_root_home.tar
root chunks/40_root_misc.tar
EOF
echo "== DEBUG: list chunks =="
ls -lh "$CHUNK_DIR" || true
# -----------------------------
# 打包生成 update.tar（包含：VERSION/install.sh/CHUNKS/chunks + uboot）
# -----------------------------
sudo rm -f "$OUT_TAR"
tar --numeric-owner --owner=0 --group=0 -C "$STAGE" -cf "$OUT_TAR" \
  VERSION install.sh CHUNKS chunks uboot

# 清理临时构建目录
rm -rf "$STAGE"

echo "== 完成 =="
echo "版本号: $VERSION"
echo "输出文件: $OUT_TAR"
