#!/bin/bash

# Пользователь и пароль
USER="vsemke"
PASSWORD="111"

# Функция для выполнения команд с автоматическим вводом пароля
run_with_sudo() {
    echo "$PASSWORD" | sudo -S "$@"
}

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# === Функции из первого скрипта (обновление ядра) ===

# Функция для получения последней версии ядра
get_latest_kernel() {
  run_with_sudo dnf info kernel-core | grep Version | awk '{print $3}' | tail -1
}

# Функция для проверки существования пакетов
check_packages() {
  for pkg in dkms akmods akmod-nvidia akmod-VirtualBox; do
    if ! rpm -q "$pkg" &>/dev/null; then
      echo "Пакет $pkg не установлен. Устанавливаю..."
      run_with_sudo dnf install -y "$pkg" || {
        echo "Ошибка: Не удалось установить $pkg."
        exit 1
      }
    fi
  done
}

# Функция для переустановки ядра
reinstall_kernel() {
  local kernel_version=$(get_latest_kernel)
  echo "Переустановка ядра kernel-core-$kernel_version..."
  #run_with_sudo dnf reinstall "kernel-core-$kernel_version" ||
  run_with_sudo dnf reinstall "$(rpm -q kernel | sort -V | tail -n 1)"
  run_with_sudo dnf reinstall "kernel-devel-$(rpm -q kernel | sort -V | tail -n 1 | sed 's/kernel-//')"
  run_with_sudo akmods --force --kernel "$(rpm -q kernel | sort -V | tail -n 1)"
  run_with_sudo dnf update akmod-nvidia nvidia-driver || {
    echo "Ошибка: Не удалось переустановить ядро."
    exit 1
  }
}

# Функция для пересоздания initramfs
rebuild_initramfs() {
  local kernel_version=$(get_latest_kernel)
  local initramfs_path="/boot/initramfs-$kernel_version.img"
  echo "Пересоздание initramfs для ядра $kernel_version..."
  run_with_sudo dracut -f "$initramfs_path" "$kernel_version" || {
    echo "Ошибка: Не удалось пересоздать initramfs."
    exit 1
  }
}

# Функция для обновления GRUB
update_grub() {
  echo "Обновление конфигурации GRUB..."
  run_with_sudo grub2-mkconfig -o /boot/grub2/grub.cfg || {
    echo "Ошибка: Не удалось обновить GRUB."
    exit 1
  }
}

# Функция для пересборки модулей NVIDIA и VirtualBox
rebuild_modules() {
  echo "Пересборка модулей NVIDIA и VirtualBox..."
  run_with_sudo akmods --force || {
    echo "Ошибка: Не удалось пересобрать модули."
    exit 1
  }

  # Получаем текущую версию ядра
  local kernel_version=$(uname -r)

  # Проверяем, существует ли директория с модулями
  if [ -d "/lib/modules/$kernel_version/extra/" ]; then
    ls /lib/modules/"$kernel_version"/extra/ && echo "Модули успешно собраны."
  else
    echo "Ошибка: Директория /lib/modules/$kernel_version/extra/ не найдена."
    exit 1
  fi
}

# Функция для обновления akmod-nvidia
update_nvidia() {
  echo "Обновление akmod-nvidia..."
  run_with_sudo dnf update -y --refresh akmod-nvidia || {
    echo "Ошибка: Не удалось обновить akmod-nvidia."
    exit 1
  }
}

# Функция для полного процесса фикса
fix_all() {
  check_packages
  reinstall_kernel
  update_nvidia
  rebuild_modules
  rebuild_initramfs
  update_grub
  echo "Все шаги выполнены. Пожалуйста, перезагрузите систему и выберите новое ядро в GRUB."
}

# === Конец функций из первого скрипта ===

# === Функции из второго скрипта (оставлены без изменений, кроме вызова через run_with_sudo) ===

update_system() {
    echo -e "${GREEN}Обновляем систему...${NC}"
    run_with_sudo dnf clean all

    # Обновление метаданных с указанным зеркалом
    run_with_sudo dnf makecache --refresh --setopt=updates.baseurl=http://dl.fedoraproject.org/pub/fedora/linux/updates/42/Everything/x86_64/
    run_with_sudo dnf check
    # Обновление системы с указанным зеркалом
    run_with_sudo dnf update -y --setopt=updates.baseurl=http://dl.fedoraproject.org/pub/fedora/linux/updates/42/Everything/x86_64/

    #run_with_sudo dnf makecache --refresh

# Обновление пакетов DNF
    run_with_sudo dnf upgrade -y
    run_with_sudo dnf update --refresh
    run_with_sudo dnf update --allowerasing

# Обновление Flatpak-пакетов
    echo -e "${GREEN}Обновляем Flatpak-пакеты...${NC}"
    flatpak update -y

}
refresh_package_list() {
    echo -e "${GREEN}Обновляем список пакетов...${NC}"
    run_with_sudo dnf makecache
}

clear_cache() {
    echo -e "${GREEN}Очищаем кэш...${NC}"
    run_with_sudo dnf clean all
}

fix_broken_dependencies() {
    echo -e "${GREEN}Исправляем сломанные зависимости...${NC}"
    run_with_sudo dnf check
    run_with_sudo dnf distro-sync -y
}

add_repository() {
    echo -e "${GREEN}Добавление репозитория...${NC}"
    read -rp "Введите URL репозитория: " repo_url
    run_with_sudo dnf config-manager --add-repo "$repo_url"
}

remove_repository() {
    echo -e "${GREEN}Удаление репозитория...${NC}"
    read -rp "Введите идентификатор или URL репозитория для удаления: " repo
    # Удаление по ID
    run_with_sudo dnf config-manager --set-disabled "$repo"
    # Удаление файла репозитория (если указан URL)
    if [[ -f "/etc/yum.repos.d/$(basename $repo)" ]]; then
        echo -e "${GREEN}Удаление файла репозитория: /etc/yum.repos.d/$(basename $repo)...${NC}"
        run_with_sudo rm -f "/etc/yum.repos.d/$(basename $repo)"
    fi
}

list_repositories() {
    echo -e "${GREEN}Список доступных репозиториев:${NC}"
    run_with_sudo dnf repolist all
    echo -e "\n${GREEN}Список зеркал для каждого репозитория:${NC}"
    run_with_sudo cat /etc/yum.repos.d/*.repo
}

install_package() {
    echo -e "${GREEN}Установка пакетов...${NC}"
    read -rp "Введите имя пакета или список пакетов для установки (через пробел): " package_names
    run_with_sudo dnf install -y $package_names
}

remove_package() {
    echo -e "${GREEN}Удаление пакетов...${NC}"
    read -rp "Введите имя пакета или список пакетов для удаления (через пробел): " package_names
    run_with_sudo dnf remove -y $package_names
    echo -e "${GREEN}Удаление ненужных зависимостей и остатков...${NC}"
    run_with_sudo dnf autoremove -y
    run_with_sudo dnf clean all
}

# === Меню ===

while true; do
    echo -e "\n${GREEN}Меню управления пакетами DNF${NC}"
    echo "1) Обновить систему"
    echo "2) Обновить список пакетов"
    echo "3) Очистить кэш"
    echo "4) Пофиксить сломанные зависимости"
    echo "5) Выполнить все шаги обновления ядра"
    echo "6) Добавить репозиторий"
    echo "7) Удалить репозиторий (по ID или URL)"
    echo "8) Посмотреть список репозиториев и зеркал"
    echo "9) Установить пакет(ы)"
    echo "10) Удалить пакет(ы)"

    read -rp "Выберите опцию (1-10): " choice
    case $choice in
        1) update_system ;;
        2) refresh_package_list ;;
        3) clear_cache ;;
        4) fix_broken_dependencies ;;
        5) fix_all ;;  # Вызов полного процесса обновления ядра
        6) add_repository ;;
        7) remove_repository ;;
        8) list_repositories ;;
        9) install_package ;;
        10) remove_package ;;
        *) echo -e "${RED}Неверный выбор. Попробуйте снова.${NC}" ;;
    esac
done
