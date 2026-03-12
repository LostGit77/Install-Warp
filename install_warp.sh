#!/bin/bash
# ===========================================
# Скрипт установки Cloudflare WARP на сервер
# ===========================================

set -e

print_msg() {
    local type="$1"
    local msg="$2"
    case "$type" in
        ok) echo -e "\e[32m[-OK-]\e[0m $msg" ;;
        info) echo -e "\e[36m[INFO]\e[0m $msg" ;;
        warn) echo -e "\e[33m[WARN]\e[0m $msg" ;;
        error) echo -e "\e[31m[ERROR]\e[0m $msg" ;;
    esac
}

check_warp_status() {
    if dpkg -l cloudflare-warp 2>/dev/null | grep -q "^ii" && command -v warp-cli >/dev/null 2>&1; then
        print_msg ok "Cloudflare WARP уже установлен"
        warp-cli status 2>/dev/null || true
        return 0
    fi
    return 1
}

wait_for_dpkg_lock() {
    while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          sudo fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        echo "[INFO] Ждем, пока другой процесс apt/dpkg завершится..."
        sleep 5
    done
}

ask_yes_no() {
    local prompt="$1"
    local reply
    while true; do
        # Жёлтый цвет для вопроса
        read -r -p $'\e[33m'"$prompt (y/n): "$'\e[0m' reply
        reply=$(echo "$reply" | tr 'A-Z' 'a-z')
        case "$reply" in
            y) return 0 ;;
            n) return 1 ;;
            *) echo -e "\e[33mВведите y или n\e[0m" ;;
        esac
    done
}

install_warp_repo() {
    print_msg info "Добавляем ключ репозитория Cloudflare..."
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor \
        > /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg
    print_msg ok "Ключ Cloudflare добавлен"

    print_msg info "Добавляем репозиторий..."
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/cloudflare-client.list
    print_msg ok "Репозиторий Cloudflare добавлен"
}

install_warp_package() {
    print_msg info "Устанавливаем WARP..."
    wait_for_dpkg_lock
    apt-get update
    wait_for_dpkg_lock
    apt-get install -y cloudflare-warp
    print_msg ok "WARP установлен"
}

register_warp() {
    print_msg info "Регистрируем WARP клиент..."
    if ! warp-cli status | grep -q "Registered"; then
        echo y | script -q -c "warp-cli registration new" /dev/null
        print_msg ok "WARP успешно зарегистрирован"
    else
        print_msg info "WARP уже зарегистрирован"
    fi
}

enable_warp_proxy() {
    print_msg info "Включаем режим прокси..."
    warp-cli mode proxy
    warp-cli connect
    print_msg ok "WARP подключен в режиме прокси"
    echo -e "\n\e[33mНастройки SOCKS для WARP в Outbounds в 3x-ui панели:\nIP: 127.0.0.1\nPORT: 40000\e[0m\n"
}

enable_warp_vpn() {
    print_msg info "Подключаем WARP в VPN режиме..."
    warp-cli connect
    print_msg ok "WARP подключен в VPN режиме"
}

setup_warp() {
    if check_warp_status; then
        return
    fi

    if ! ask_yes_no "Установить Cloudflare WARP?"; then
        print_msg info "Установка WARP пропущена пользователем"
        return
    fi

    install_warp_repo
    install_warp_package
    register_warp

    if ask_yes_no "Использовать WARP как SOCKS-прокси для панели 3x-ui (или 'n' для VPN режима):"; then
        enable_warp_proxy
    else
        enable_warp_vpn
    fi

    print_msg info "Статус WARP:"
    warp-cli status
}

# ================================
# Запуск
# ================================

setup_warp
