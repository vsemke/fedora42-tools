#!/bin/bash

# Пользователь и пароль
USER="vsemke"
PASSWORD="111"

# Цвета для оформления
BOLD='\033[1m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
UNDERLINE='\033[4m'
ITALIC='\033[3m'

# Функция для выполнения команд с автоматическим вводом пароля
run_with_sudo() {
    echo "$PASSWORD" | sudo -S "$@"
}

# --- Функции из первого меню ---
# Функция для отображения топ-5 процессов
show_top_processes() {
    clear
    echo -e "${BLUE}${BOLD}=== Топ-5 процессов по CPU ===${NC}"
    ps -eo pid,ppid,cmd,%cpu --sort=-%cpu | head -n 6 | awk '{print "\033[1;32m" $0 "\033[0m"}'
    echo ""
    echo -e "${BLUE}${BOLD}=== Топ-5 процессов по RAM ===${NC}"
    ps -eo pid,ppid,cmd,%mem --sort=-%mem | head -n 6 | awk '{print "\033[1;32m" $0 "\033[0m"}'
    echo ""
    echo -e "${YELLOW}Нажмите Enter, чтобы вернуться в меню...${NC}"
    read
}

# Функция для запуска iftop
run_iftop() {
    clear
    echo -e "${BLUE}${BOLD}Запуск iftop...${NC}"
    run_with_sudo iftop
    echo -e "${YELLOW}Нажмите Enter, чтобы вернуться в меню...${NC}"
    read
}

# --- Функции из второго скрипта (монтирование шаров) ---
# Адреса серверов
LOCAL_IP="192.168.10.100"
ZT_IP="192.168.192.100"

# Список шаров и точек монтирования
SHARES=("Disk1" "Disk2" "Disk3" "MULTIMEDIA" "SSD")
MOUNT_POINTS=("/media/Disk1" "/media/Disk2" "/media/Disk3" "/media/MULTIMEDIA" "/media/SSD")

# Переменные для хранения уведомлений
MOUNTED=""
UNMOUNTED=""

mount_unmount_shares() {
    clear
    echo -e "${BLUE}${BOLD}=== Управление монтированием шаров ===${NC}"
    # Перезапуск демона ZeroTier
    echo -e "${YELLOW}Перезапуск службы ZeroTier...${NC}"
    run_with_sudo systemctl restart zerotier-one
    sleep 2

    # Функция для монтирования шары с полными правами
    mount_share() {
        local ip=$1
        local share=$2
        local mount_point=$3
        if [ ! -d "$mount_point" ]; then
            echo -e "${YELLOW}Создаём папку $mount_point${NC}"
            run_with_sudo mkdir -p "$mount_point" || { echo -e "${RED}Ошибка при создании $mount_point${NC}"; return 1; }
        fi
        if run_with_sudo mount.cifs "//${ip}/${share}" "${mount_point}" -o guest,uid=1000,gid=1000,file_mode=0777,dir_mode=0777; then
            MOUNTED="$MOUNTED${mount_point##*/}\n"
        else
            echo -e "${RED}Не удалось смонтировать $mount_point${NC}"
        fi
    }

    # Функция для отмонтирования и удаления
    umount_and_remove() {
        local mount_point=$1
        if mountpoint -q "$mount_point"; then
            echo -e "${YELLOW}Отмонтируем $mount_point${NC}"
            if run_with_sudo umount "$mount_point"; then
                UNMOUNTED="$UNMOUNTED${mount_point##*/}\n"
            else
                echo -e "${RED}Не удалось отмонтировать $mount_point${NC}"
            fi
        fi
        if [ -d "$mount_point" ]; then
            echo -e "${YELLOW}Удаляем папку $mount_point${NC}"
            run_with_sudo rmdir "$mount_point"
        fi
    }

    # Основная логика
    all_mounted=true
    for mount_point in "${MOUNT_POINTS[@]}"; do
        if ! mountpoint -q "$mount_point"; then
            all_mounted=false
            break
        fi
    done

    if [ "$all_mounted" = true ]; then
        echo -e "${YELLOW}Все точки монтирования уже смонтированы, выполняем отмонтирование и удаление${NC}"
        for mount_point in "${MOUNT_POINTS[@]}"; do
            umount_and_remove "$mount_point"
        done
        if [ -n "$UNMOUNTED" ]; then
            echo -e "${GREEN}\nУспешно отмонтированы следующие папки:\n$UNMOUNTED${NC}"
        else
            echo -e "${RED}\nНи одна папка не была отмонтирована.${NC}"
        fi
    else
        if ping -c 1 -W 1 "$LOCAL_IP" &> /dev/null; then
            echo -e "${GREEN}Локальный сервер доступен, монтируем с $LOCAL_IP${NC}"
            for i in "${!SHARES[@]}"; do
                mount_share "$LOCAL_IP" "${SHARES[$i]}" "${MOUNT_POINTS[$i]}"
            done
        elif ping -c 1 -W 1 "$ZT_IP" &> /dev/null; then
            echo -e "${YELLOW}Локальный сервер недоступен, монтируем через ZeroTier с $ZT_IP${NC}"
            for i in "${!SHARES[@]}"; do
                mount_share "$ZT_IP" "${SHARES[$i]}" "${MOUNT_POINTS[$i]}"
            done
        else
            echo -e "${RED}Оба сервера недоступны${NC}"
        fi
        if [ -n "$MOUNTED" ]; then
            echo -e "${GREEN}\nУспешно смонтированы следующие папки:\n$MOUNTED${NC}"
        else
            echo -e "${RED}\nНи одна папка не была смонтирована.${NC}"
        fi
    fi
    echo -e "${YELLOW}\nНажмите Enter, чтобы вернуться в меню...${NC}"
    read
}

# --- Функции из третьего скрипта (ZeroTier маршрутизация) ---
ZT_GATEWAY="192.168.192.35"
ZT_INTERFACE="ztugayu2f5"

# Поиск шлюза по умолчанию
find_default_gateway() {
    local gateways
    gateways=$(ip route show default | grep -oP 'default via \K[\d.]+' | grep -v "$ZT_GATEWAY")
    if [ -n "$gateways" ]; then
        echo "$gateways" | head -1
    else
        for gw in 192.168.0.1 192.168.1.1 192.168.2.1 192.168.10.1; do
            if ping -c 1 -W 1 "$gw" > /dev/null 2>&1; then
                echo "$gw"
                return
            fi
        done
        echo ""
    fi
}

find_default_interface() {
    local gateway=$1
    if [ -n "$gateway" ]; then
        ip route show default | grep "via $gateway" | grep -oP 'dev \K\w+' | head -1
    else
        ip route show default | grep -oP 'dev \K\w+' | grep -v "$ZT_INTERFACE" | head -1
    fi
}

DEFAULT_GATEWAY=$(find_default_gateway)
DEFAULT_INTERFACE=$(find_default_interface "$DEFAULT_GATEWAY")

# Проверка шлюза и интерфейса
if [ -z "$DEFAULT_GATEWAY" ] || [ -z "$DEFAULT_INTERFACE" ]; then
    echo -e "${RED}${BOLD}Ошибка: Не удалось определить локальный шлюз или интерфейс.${NC}"
    echo -e "${YELLOW}Проверьте вывод команды 'ip route show default' или доступность шлюза.${NC}"
    exit 1
fi

# Проверка статуса ZeroTier
check_zt_status() {
    clear
    echo -e "${YELLOW}${BOLD}Проверка статуса ZeroTier...${NC}"
    run_with_sudo zerotier-cli status > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}${BOLD}Ошибка: ZeroTier не работает или не установлен.${NC}"
        read -p "$(echo -e ${BLUE}Перезапустить сервис ZeroTier? [y/N]: ${NC})" choice
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}${BOLD}Перезапускаем ZeroTier...${NC}"
            run_with_sudo systemctl restart zerotier-one
            sleep 2
            run_with_sudo zerotier-cli status
            if [ $? -ne 0 ]; then
                echo -e "${RED}${BOLD}Не удалось запустить ZeroTier. Проверьте установку и конфигурацию.${NC}"
                exit 1
            fi
            echo -e "${GREEN}${BOLD}ZeroTier успешно запущен!${NC}"
        else
            echo -e "${RED}${BOLD}Выход из программы, так как ZeroTier неактивен.${NC}"
            exit 1
        fi
    else
        run_with_sudo zerotier-cli status
    fi
    echo -e "${YELLOW}Нажмите Enter, чтобы вернуться в меню...${NC}"
    read
}

# Включение маршрутизации через ZeroTier
enable_zt() {
    clear
    echo -e "${GREEN}${BOLD}Включаем маршрутизацию через ZeroTier...${NC}"
    run_with_sudo ip route add $ZT_GATEWAY/32 via $DEFAULT_GATEWAY dev $DEFAULT_INTERFACE
    run_with_sudo ip route replace default via $ZT_GATEWAY dev $ZT_INTERFACE
    echo -e "${GREEN}Интернет теперь идет через ZeroTier (${ZT_GATEWAY}).${NC}"
    echo -e "${YELLOW}Нажмите Enter, чтобы вернуться в меню...${NC}"
    read
}

# Отключение маршрутизации через ZeroTier
disable_zt() {
    clear
    echo -e "${YELLOW}${BOLD}Отключаем маршрутизацию через ZeroTier...${NC}"
    run_with_sudo ip route replace default via $DEFAULT_GATEWAY dev $DEFAULT_INTERFACE
    run_with_sudo ip route del $ZT_GATEWAY/32 2>/dev/null
    echo -e "${YELLOW}Интернет восстановлен через локальный шлюз (${DEFAULT_GATEWAY}).${NC}"
    echo -e "${YELLOW}Нажмите Enter, чтобы вернуться в меню...${NC}"
    read
}

# Меню управления ZeroTier
zt_menu() {
    while true; do
        clear
        echo -e "${RED}${BOLD}=============================${NC}"
        echo -e "${GREEN}${BOLD}   МЕНЮ УПРАВЛЕНИЯ ZEROTIER  ${NC}"
        echo -e "${RED}${BOLD}=============================${NC}"
        echo -e "${YELLOW}${ITALIC}1. Проверить статус ZeroTier${NC}"
        echo -e "${YELLOW}${ITALIC}2. Включить интернет через VDS (ZeroTier)${NC}"
        echo -e "${YELLOW}${ITALIC}3. Отключить и вернуть локальный интернет${NC}"
        echo -e "${YELLOW}${ITALIC}4. Вернуться в главное меню${NC}"
        echo -e "${RED}${BOLD}=============================${NC}"
        read -p "$(echo -e ${BLUE}Введите номер [1-4]: ${NC})" choice

        case $choice in
            1) check_zt_status ;;
            2) enable_zt ;;
            3) disable_zt ;;
            4) break ;;
            *)
                clear
                echo -e "${RED}${BOLD}Неверный выбор. Выберите 1, 2, 3 или 4.${NC}"
                sleep 2
                ;;
        esac
    done
}

# Основное глобальное меню
while true; do
    clear
    echo -e "${RED}${BOLD}=============================${NC}"
    echo -e "${GREEN}${BOLD}   ГЛОБАЛЬНОЕ МЕНЮ УПРАВЛЕНИЯ FEDORA  ${NC}"
    echo -e "${RED}${BOLD}=============================${NC}"
    echo -e "${YELLOW}1. Показать топ-5 процессов по CPU и RAM${NC}"
    echo -e "${YELLOW}2. Запустить iftop${NC}"
    echo -e "${YELLOW}3. Установить модули VMware${NC}"
    echo -e "${YELLOW}4. Запустить VMware Player${NC}"
    echo -e "${YELLOW}5. Управление монтированием шаров${NC}"
    echo -e "${YELLOW}6. ${UNDERLINE}Меню управления ZeroTier${NC}"
    echo -e "${YELLOW}7. Выход${NC}"
    echo -e "${RED}${BOLD}=============================${NC}"
    read -p "$(echo -e ${BLUE}Введите номер [1-7]: ${NC})" choice

    case $choice in
        1) show_top_processes ;;
        2) run_iftop ;;
        3)
            clear
            echo -e "${BLUE}${BOLD}Установка модулей VMware...${NC}"
            run_with_sudo vmware-modconfig --console --install-all
            echo -e "${YELLOW}Нажмите Enter, чтобы вернуться в меню...${NC}"
            read
            ;;
        4)
            clear
            echo -e "${BLUE}${BOLD}Запуск VMware Player...${NC}"
            run_with_sudo -i vmplayer
            echo -e "${YELLOW}Нажмите Enter, чтобы вернуться в меню...${NC}"
            read
            ;;
        5) mount_unmount_shares ;;
        6) zt_menu ;;
        7)
            clear
            echo -e "${GREEN}${BOLD}Выход из программы.${NC}"
            exit 0
            ;;
        *)
            clear
            echo -e "${RED}${BOLD}Неверный выбор. Выберите 1-7.${NC}"
            sleep 2
            ;;
    esac
done
