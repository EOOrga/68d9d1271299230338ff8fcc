#!/usr/bin/env bash

set -u

export PATH="/home/simo/Android/Sdk/platform-tools:${PATH}"

AGENT="$(basename "${PWD}")"
QUEUE_URL="http://localhost:3000"
APP_ID="fr.kersylva.operations"
APK_PATH="${SCREENSHOT_APK:-/tmp/kersylva-universal.apk}"
SCREENS_DIR="docs/screens"

log() {
  printf '%s %s\n' "$(date '+%H:%M:%S')" "$*"
}

join_queue() {
  curl -s -X POST "${QUEUE_URL}/join?agent=${AGENT}" >/dev/null || true
}

release_queue() {
  curl -s -X POST "${QUEUE_URL}/done?agent=${AGENT}" >/dev/null || true
}

status_queue() {
  curl -s "${QUEUE_URL}/status?agent=${AGENT}" || true
}

is_turn() {
  printf '%s' "$1" | grep -Eq '"yourTurn"[[:space:]]*:[[:space:]]*true'
}

not_in_queue() {
  printf '%s' "$1" | grep -qi 'not in queue'
}

short_json() {
  printf '%s' "$1" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g'
}

online_device() {
  adb devices | awk 'NR > 1 && $1 ~ /^emulator-/ && $2 == "device" { print $1; exit }'
}

pixel_qemu_count() {
  ps -C qemu-system-x86_64 -o args= 2>/dev/null | awk '/ -avd Pixel_8_Pro( |$)/ { c++ } END { print c + 0 }'
}

current_turn() {
  local status
  status="$(status_queue)"
  is_turn "${status}"
}

wait_for_resources() {
  while true; do
    local mem_kb disk_kb load qemu
    mem_kb="$(awk '/MemAvailable/ { print $2; exit }' /proc/meminfo)"
    disk_kb="$(df -Pk . | awk 'NR == 2 { print $4 }')"
    load="$(awk '{ print $1 }' /proc/loadavg)"
    qemu="$(pixel_qemu_count)"
    log "resource check mem_available_kb=${mem_kb:-0} disk_available_kb=${disk_kb:-0} load1=${load} qemu=${qemu}"
    [[ "${mem_kb:-0}" -ge 2500000 && "${disk_kb:-0}" -ge 1500000 ]] && return 0
    sleep 60
    current_turn || return 2
  done
}

wait_for_boot() {
  BOOT_DEV=""
  local deadline=$((SECONDS + 900))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    current_turn || {
      log "queue turn changed while waiting for boot"
      return 2
    }

    local dev qemu boot
    dev="$(online_device || true)"
    qemu="$(pixel_qemu_count)"
    if [[ -n "${dev}" ]]; then
      boot="$(adb -s "${dev}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
      log "boot check dev=${dev} boot=${boot:-waiting} qemu=${qemu}"
      if [[ "${boot}" == "1" ]]; then
        BOOT_DEV="${dev}"
        return 0
      fi
    else
      log "boot check dev=none qemu=${qemu}"
    fi
    sleep 5
  done
  return 1
}

ensure_pixel_device() {
  local dev="$1" avd
  avd="$(adb -s "${dev}" emu avd name 2>/dev/null | tr -d '\r' | sed '/^OK$/d;/^$/d' | head -n 1 || true)"
  log "using device=${dev} avd=${avd}"
  [[ "${avd}" == "Pixel_8_Pro" ]]
}

ensure_focus() {
  local dev="$1" focus
  for _ in $(seq 1 8); do
    focus="$(adb -s "${dev}" shell dumpsys window 2>/dev/null | grep -E 'mCurrentFocus|mFocusedApp' | head -n 4 || true)"
    log "focus=$(printf '%s' "${focus}" | tr '\n' ' ')"
    if printf '%s' "${focus}" | grep -q "${APP_ID}"; then
      return 0
    fi
    adb -s "${dev}" shell am start -W -n "${APP_ID}/.MainActivity" >/dev/null 2>&1 || true
    sleep 1
  done
  return 1
}

capture_png() {
  local dev="$1" name="$2" bytes
  ensure_focus "${dev}" || return 1
  adb -s "${dev}" exec-out screencap -p > "${SCREENS_DIR}/${name}.png" || return 1
  bytes="$(wc -c < "${SCREENS_DIR}/${name}.png" | tr -d ' ')"
  file "${SCREENS_DIR}/${name}.png"
  log "captured ${name} bytes=${bytes}"
  [[ "${bytes}" -gt 100000 ]]
}

tap_nav() {
  local dev="$1" index="$2" width="$3" height="$4"
  local x=$((width * (2 * index + 1) / 10))
  local y=$((height - 135))
  adb -s "${dev}" shell input tap "${x}" "${y}" >/dev/null
  sleep 3
}

capture_run() {
  local dev="$1" screen_size width height count unique small dims
  [[ -s "${APK_PATH}" ]] || {
    log "missing APK ${APK_PATH}"
    return 1
  }
  ensure_pixel_device "${dev}" || return 1

  adb -s "${dev}" shell input keyevent KEYCODE_WAKEUP >/dev/null 2>&1 || true
  adb -s "${dev}" shell wm dismiss-keyguard >/dev/null 2>&1 || true
  adb -s "${dev}" shell pm uninstall "${APP_ID}" >/dev/null 2>&1 || true
  log "installing ${APK_PATH}"
  adb -s "${dev}" install --no-streaming -r "${APK_PATH}" || return 1
  screen_size="$(adb -s "${dev}" shell wm size 2>/dev/null | tr -d '\r' | awk '/Physical size/ { print $3; exit }')"
  width="${screen_size%x*}"
  height="${screen_size#*x}"
  case "${width:-}:${height:-}" in
    *[!0-9:]*|:*)
      log "bad phone size: ${screen_size:-unknown}"
      return 1
      ;;
  esac
  log "phone capture size=${width}x${height}"
  [[ "${height}" -gt "${width}" && "${width}" -ge 1000 && "${height}" -ge 1800 ]] || return 1

  mkdir -p "${SCREENS_DIR}"
  find "${SCREENS_DIR}" -maxdepth 1 -type f -name '*.png' -delete
  touch "${SCREENS_DIR}/.gitkeep"

  local team_x spend_x quality_x agenda_x nav_y fab_x fab_y
  team_x=$((width * 3 / 10))
  spend_x=$((width * 5 / 10))
  quality_x=$((width * 7 / 10))
  agenda_x=$((width * 9 / 10))
  nav_y=$((height - 135))
  fab_x=$((width - 210))
  fab_y=$((height - 340))

  log "capturing screens in one device-side sequence"
  adb -s "${dev}" shell "
    rm -f /sdcard/kersylva_ops_*.png
    am force-stop ${APP_ID}; am start -W -n ${APP_ID}/.MainActivity >/dev/null; sleep 3; screencap -p /sdcard/kersylva_ops_01_home.png
    am force-stop ${APP_ID}; am start -W -n ${APP_ID}/.MainActivity >/dev/null; sleep 2; input tap ${team_x} ${nav_y}; sleep 1; screencap -p /sdcard/kersylva_ops_02_team.png
    am force-stop ${APP_ID}; am start -W -n ${APP_ID}/.MainActivity >/dev/null; sleep 2; input tap ${spend_x} ${nav_y}; sleep 1; screencap -p /sdcard/kersylva_ops_03_expenses.png
    am force-stop ${APP_ID}; am start -W -n ${APP_ID}/.MainActivity >/dev/null; sleep 2; input tap ${spend_x} ${nav_y}; sleep 1; input tap ${fab_x} ${fab_y}; sleep 1; screencap -p /sdcard/kersylva_ops_04_expense_form.png
    am force-stop ${APP_ID}; am start -W -n ${APP_ID}/.MainActivity >/dev/null; sleep 2; input tap ${quality_x} ${nav_y}; sleep 1; screencap -p /sdcard/kersylva_ops_05_quality.png
    am force-stop ${APP_ID}; am start -W -n ${APP_ID}/.MainActivity >/dev/null; sleep 2; input tap ${agenda_x} ${nav_y}; sleep 1; screencap -p /sdcard/kersylva_ops_06_agenda.png
  " || return 1

  for name in 01_home 02_team 03_expenses 04_expense_form 05_quality 06_agenda; do
    adb -s "${dev}" exec-out cat "/sdcard/kersylva_ops_${name}.png" > "${SCREENS_DIR}/${name}.png" || return 1
    file "${SCREENS_DIR}/${name}.png"
    log "captured ${name} bytes=$(wc -c < "${SCREENS_DIR}/${name}.png" | tr -d ' ')"
  done

  count="$(find "${SCREENS_DIR}" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
  unique="$(sha256sum "${SCREENS_DIR}"/*.png 2>/dev/null | awk '{ print $1 }' | sort -u | wc -l | tr -d ' ')"
  small="$(find "${SCREENS_DIR}" -maxdepth 1 -type f -name '*.png' -size -100k | wc -l | tr -d ' ')"
  dims="$(file "${SCREENS_DIR}"/*.png | sed -E 's|.*/([^/]+): PNG image data, ([0-9]+ x [0-9]+).*|\1=\2|' | tr '\n' ' ')"
  log "screens count=${count} unique=${unique} small=${small} dims=${dims}"
  [[ "${count}" -ge 6 && "${unique}" -ge 5 && "${small}" == "0" ]]
}

join_queue
while true; do
  status="$(status_queue)"
  log "$(short_json "${status}")"
  if not_in_queue "${status}"; then
    join_queue
    sleep 10
    continue
  fi
  if ! is_turn "${status}"; then
    sleep 10
    continue
  fi

  log "queue turn acquired; checking adb devices before launch"
  adb devices -l || true
  wait_for_resources || continue

  dev="$(online_device || true)"
  qemu="$(pixel_qemu_count)"
  if [[ -n "${dev}" ]]; then
    boot="$(adb -s "${dev}" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)"
    log "existing emulator dev=${dev} boot=${boot:-waiting} qemu=${qemu}"
    if [[ "${boot}" != "1" ]]; then
      wait_for_boot || {
        log "existing emulator did not finish booting; release/rejoin"
        release_queue
        join_queue
        sleep 10
        continue
      }
      dev="${BOOT_DEV}"
    fi
  elif [[ "${qemu}" != "0" ]]; then
    log "Pixel_8_Pro process already present; waiting for adb instead of launching another"
    if ! wait_for_boot; then
      log "stale Pixel_8_Pro process never reached adb; release/rejoin"
      release_queue
      join_queue
      sleep 10
      continue
    fi
    dev="${BOOT_DEV}"
  else
    log "launching Pixel_8_Pro with visible UI"
    flutter emulators --launch Pixel_8_Pro || true
    if ! wait_for_boot; then
      log "Pixel_8_Pro did not boot in time; release/rejoin"
      release_queue
      join_queue
      sleep 10
      continue
    fi
    dev="${BOOT_DEV}"
  fi

  if capture_run "${dev}"; then
    adb -s "${dev}" shell pm uninstall "${APP_ID}" >/dev/null 2>&1 || true
    release_queue
    log "screenshots captured, app uninstalled, queue released"
    exit 0
  fi

  log "capture failed; uninstalling app, releasing, and rejoining"
  adb -s "${dev}" shell pm uninstall "${APP_ID}" >/dev/null 2>&1 || true
  release_queue
  sleep 2
  join_queue
  sleep 10
done
