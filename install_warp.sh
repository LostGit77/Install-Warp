#!/bin/bash
# ===========================================
# Установка Cloudflare WARP (ТОЛЬКО PROXY)
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
        print_msg info "Ждем завершения apt/dpkg..."
        sleep 5
    done
}

ask_warp_install() {
    local reply
    while true; do
        read -r -p $'\e[33mУстановить Cloudflare WARP в режиме SOCKS-прокси? (y/n): \e[0m' reply
        reply=$(echo "$reply" | tr 'A-Z' 'a-z')
        case "$reply" in
            y) return 0 ;;
            n) return 1 ;;
            *) print_msg warn "Введите y или n" ;;
        esac
    done
}

install_warp_repo() {
    print_msg info "Добавляем ключ Cloudflare..."
    curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --yes --dearmor \
        > /usr/share/keyrings/cloudflare-warp-archive-keyring.gpg

    print_msg info "Добавляем репозиторий..."
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-warp-archive-keyring.gpg] https://pkg.cloudflareclient.com/ $(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/cloudflare-client.list

    print_msg ok "Репозиторий добавлен"
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
    print_msg info "Регистрируем WARP..."
    if ! warp-cli status | grep -q "Registered"; then
        echo y | script -q -c "warp-cli registration new" /dev/null
        print_msg ok "WARP зарегистрирован"
    else
        print_msg info "Уже зарегистрирован"
    fi
}

enable_warp_proxy() {
    print_msg info "Включаем proxy режим..."
    warp-cli mode proxy
    warp-cli connect

    print_msg ok "WARP работает в режиме SOCKS"

    echo
    print_msg warn "Настройки для 3x-ui:"
    echo "IP:   127.0.0.1"
    echo "PORT: 40000"
    echo
}

setup_warp() {
    if check_warp_status; then
        print_msg info "Пропускаем установку"
        return
    fi

    if ! ask_warp_install; then
        print_msg info "Отменено пользователем"
        return
    fi

    install_warp_repo
    install_warp_package
    register_warp
    enable_warp_proxy

    print_msg info "Статус WARP:"
    warp-cli status
}

# ================================
# Запуск
# ================================

setup_warp
