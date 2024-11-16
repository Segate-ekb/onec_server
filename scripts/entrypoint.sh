#!/bin/bash
set -ex  # Прерываем выполнение при ошибках

# Функция для чтения переменных окружения или их вариантов с суффиксом __FILE
read_env_or_file() {
  local var_name="$1"
  local file_var_name="${var_name}__FILE"
  local value=""

  if [ -n "${!file_var_name}" ]; then
    echo "Чтение значения из файла: ${!file_var_name}" >&2
    if [ -f "${!file_var_name}" ]; then
      value=$(cat "${!file_var_name}")
    else
      echo "Ошибка: Файл ${!file_var_name} не найден." >&2
      exit 1
    fi
  elif [ -n "${!var_name}" ]; then
    echo "Чтение значения из переменной окружения: $var_name" >&2
    value="${!var_name}"
  else
    echo "Переменная $var_name не задана." >&2
  fi

  echo "$value"
}

# Функция для проверки, что переменная окружения задана
check_env_var() {
  local var_name="$1"
  local var_value="$2"
  if [ -z "$var_value" ]; then
    echo "Ошибка: Переменная окружения $var_name не задана. Завершение работы." >&2
    exit 1
  fi
}

# Функция для поиска пути к установленной платформе 1С
find_platform_path() {
  platform_path=$(find /opt/1cv8/x86_64/ -maxdepth 1 -type d -name "$ONEC_VERSION" 2>/dev/null)

  if [ -z "$platform_path" ]; then
    echo "Платформа 1С версии $ONEC_VERSION не найдена." >&2
    return 1
  else
    echo "Найдена установленная платформа 1С по пути: $platform_path" >&2
    return 0
  fi
}

# Функция для создания символической ссылки /opt/1cv8/current
create_symlink() {
  mkdir -p /opt/1cv8
  ln -sfn "$platform_path" /opt/1cv8/current
  echo "Создана символическая ссылка /opt/1cv8/current на $platform_path" >&2
}

# Функция для скачивания сервера 1С
download_1c_server() {
  # Чтение переменных окружения или файлов с секретами
  ONEC_USERNAME=$(read_env_or_file "ONEC_USERNAME")
  ONEC_PASSWORD=$(read_env_or_file "ONEC_PASSWORD")
  ONEC_VERSION=$(read_env_or_file "ONEC_VERSION")

  # Проверяем, что версия 1С задана
  check_env_var "ONEC_VERSION" "$ONEC_VERSION"

  DOWNLOADS_PATH="/tmp/downloads/Platform83/${ONEC_VERSION}"

  echo "Проверяем наличие установленной платформы 1С версии $ONEC_VERSION..." >&2

  if find_platform_path; then
    # Платформа найдена, создаем символическую ссылку
    create_symlink
  else
    # Платформа не найдена, необходимо скачать и установить
    echo "Сервер 1С не найден. Начинаю скачивание и установку." >&2

    # Проверяем, что логин и пароль заданы перед скачиванием
    check_env_var "ONEC_USERNAME" "$ONEC_USERNAME"
    check_env_var "ONEC_PASSWORD" "$ONEC_PASSWORD"

    # Создаем директорию для загрузки и очищаем ее
    mkdir -p "$DOWNLOADS_PATH"
    rm -f "$DOWNLOADS_PATH/.gitkeep"
    chmod 777 -R /tmp

    # Преобразование версии для различных целей
    ONEC_VERSION_DOTS="$ONEC_VERSION"
    ONEC_VERSION_UNDERSCORES=$(echo "$ONEC_VERSION_DOTS" | sed 's/\./\_/g')
    ESCAPED_VERSION=$(echo "$ONEC_VERSION_DOTS" | sed 's/\./\\./g')

    # Функция для проверки наличия локального дистрибутива
    check_local_distr() {
      local found=1
      local found_run_file=1

      local file_name_srv="deb64_${ONEC_VERSION_UNDERSCORES}.tar.gz"
      local file_name_platform="server64_${ONEC_VERSION_UNDERSCORES}.tar.gz"
      local file_name_run="setup-full-${ONEC_VERSION_DOTS}-x86_64.run"

      if [ -f "/distr/$file_name_srv" ]; then
        echo "Найден локальный дистрибутив: $file_name_srv" >&2
        cp "/distr/$file_name_srv" "$DOWNLOADS_PATH/"
        found=0
      elif [ -f "/distr/$file_name_platform" ]; then
        echo "Найден локальный дистрибутив: $file_name_platform" >&2
        cp "/distr/$file_name_platform" "$DOWNLOADS_PATH/"
        found=0
      elif [ -f "/distr/$file_name_run" ]; then
        echo "Найден локальный дистрибутив: $file_name_run" >&2
        cp "/distr/$file_name_run" "$DOWNLOADS_PATH/"
        found=0
        found_run_file=0
      fi

      if [ $found -eq 0 ] && [ $found_run_file -eq 1 ]; then
        # Распаковка скачанных файлов
        for file in "$DOWNLOADS_PATH"/*.tar.gz; do
          tar -xzf "$file" -C "$DOWNLOADS_PATH"
          rm -f "$file"
        done
      fi

      return $found
    }

    # Функция проверки наличия нужных файлов после распаковки
    check_file() {
      local found=1
      if ls "$DOWNLOADS_PATH"/*.deb 1> /dev/null 2>&1 || ls "$DOWNLOADS_PATH"/*.run 1> /dev/null 2>&1; then
        echo "Дистрибутив найден и готов к установке." >&2
        found=0
      else
        echo "Не найден дистрибутив сервера 1С в каталоге $DOWNLOADS_PATH" >&2
      fi
      return $found
    }

    # Функция для скачивания дистрибутива через yard
    try_download() {
      local APP_FILTER="Технологическая платформа *8\.3"
      local DISTR_FILTERS="Технологическая платформа 1С:Предприятия \(64\-bit\) для Linux$|Сервер 1С:Предприятия \(64\-bit\) для DEB-based Linux-систем$"
      local download_success=1

      IFS='|'
      read -ra FILTERS <<< "$DISTR_FILTERS"
      for filter in "${FILTERS[@]}"; do
        echo "Попытка скачать дистрибутив с фильтром: $filter" >&2
        yard releases -u "$ONEC_USERNAME" -p "$ONEC_PASSWORD" get \
          --app-filter "$APP_FILTER" \
          --version-filter "$ESCAPED_VERSION" \
          --path /tmp/downloads \
          --distr-filter "$filter" \
          --download-limit 1

        # Отключаем set -e перед вызовом функции
        set +e
        check_file
        download_success=$?
        set -e

        if [ $download_success -eq 0 ]; then
          break
        fi
      done
      return $download_success
    }

    # Основная логика скачивания
    cd "$DOWNLOADS_PATH"

    # Отключаем set -e перед вызовом функции
    set +e
    check_local_distr
    local_distr_found=$?
    set -e

    if [ $local_distr_found -ne 0 ]; then
      echo "Локальный дистрибутив не найден. Попытка скачать через yard." >&2
      if [ "$ONEC_VERSION" = "8.3.24.1342" ] || [ "$ONEC_VERSION" = "8.3.24.1368" ]; then
        echo "Ошибка: Скачивание версии $ONEC_VERSION не поддерживается. Поместите дистрибутив в папку /distr." >&2
        exit 1
      else
        echo "Версия 1С: $ONEC_VERSION" >&2
      fi
      try_download
      download_attempted=$?
      if [ $download_attempted -ne 0 ]; then
        echo "Ошибка: не удалось найти дистрибутив ни локально, ни удаленно." >&2
        exit 1
      fi
    fi

    echo "Дистрибутив сервера 1С готов к установке." >&2
    # После успешного скачивания устанавливаем сервер
    install_1c_server
  fi
}

# Функция для установки сервера 1С
install_1c_server() {
  echo "Начинаю установку сервера 1С." >&2

  # Переходим в каталог с дистрибутивом
  cd "$DOWNLOADS_PATH"

  # Функция установки из .deb пакетов
  install_from_deb() {
    echo "Установка из .deb пакетов" >&2
    dpkg -i 1c-enterprise*-{common,server}_*.deb || apt-get install -f -y
  }

  # Функция установки из .run файла
  install_from_run() {
    echo "Установка из .run файла" >&2
    local run_file=$(ls *.run | head -1)

    if [ -z "$run_file" ]; then
      echo "Не найден файл установки .run" >&2
      exit 1
    fi

    chmod +x "$run_file"
    ./"$run_file" --mode unattended --enable-components server,ws,config_storage_server,ru
  }

  # Определяем, есть ли .deb или .run файлы и устанавливаем
  if ls *.deb 1> /dev/null 2>&1; then
    install_from_deb
  elif ls *.run 1> /dev/null 2>&1; then
    install_from_run
  else
    echo "Не найдены файлы установки" >&2
    exit 1
  fi

  echo "Сервер 1С успешно установлен." >&2

  # Ищем путь к установленной платформе
  if find_platform_path; then
    # Создаем символическую ссылку
    create_symlink
  else
    echo "Ошибка: Не удалось найти установленную платформу после установки." >&2
    exit 1
  fi
}

# Установка значений по умолчанию
setup_defaults() {
  DEFAULT_PORT=1540
  DEFAULT_REGPORT=1541
  DEFAULT_RANGE=1560:1591
  DEFAULT_SECLEVEL=0
  DEFAULT_PINGPERIOD=1000
  DEFAULT_PINGTIMEOUT=5000
  DEFAULT_DEBUG=-tcp
  DEFAULT_DEBUGSERVERPORT=1550
  DEFAULT_RAS_PORT=1545
}

# Настройка команды запуска ragent
setup_ragent_cmd() {
  RAGENT_CMD="gosu usr1cv8 /opt/1cv8/current/ragent"
  RAGENT_CMD+=" /port ${PORT:-$DEFAULT_PORT}"
  RAGENT_CMD+=" /regport ${REGPORT:-$DEFAULT_REGPORT}"
  RAGENT_CMD+=" /range ${RANGE:-$DEFAULT_RANGE}"
  RAGENT_CMD+=" /seclev ${SECLEVEL:-$DEFAULT_SECLEVEL}"
  RAGENT_CMD+=" /d ${D:-/home/usr1cv8/.1cv8}"
  RAGENT_CMD+=" /pingPeriod ${PINGPERIOD:-$DEFAULT_PINGPERIOD}"
  RAGENT_CMD+=" /pingTimeout ${PINGTIMEOUT:-$DEFAULT_PINGTIMEOUT}"
  RAGENT_CMD+=" /debug ${DEBUG:-$DEFAULT_DEBUG}"

  if [ -n "$DEBUGSERVERADDR" ]; then
    RAGENT_CMD+=" /debugServerAddr $DEBUGSERVERADDR"
  fi

  RAGENT_CMD+=" /debugServerPort ${DEBUGSERVERPORT:-$DEFAULT_DEBUGSERVERPORT}"

  if [ -n "$DEBUGSERVERPWD" ]; then
    RAGENT_CMD+=" /debugServerPwd $DEBUGSERVERPWD"
  fi
}

# Настройка команды запуска ras
setup_ras_cmd() {
  RAS_CMD="gosu usr1cv8 /opt/1cv8/current/ras cluster --daemon"
  RAS_CMD+=" --port ${RAS_PORT:-$DEFAULT_RAS_PORT}"
  RAS_CMD+=" localhost:${PORT:-$DEFAULT_PORT}"
}

# Изменение прав доступа к директории пользователя
change_directory_permissions() {
  chown -R usr1cv8:grp1cv8 /home/usr1cv8
}

# Главная функция скрипта
main() {
  setup_defaults
  change_directory_permissions

  # Проверяем, что версия 1С задана
  ONEC_VERSION=$(read_env_or_file "ONEC_VERSION")
  check_env_var "ONEC_VERSION" "$ONEC_VERSION"

  # Проверяем и устанавливаем сервер 1С, если он не установлен
  download_1c_server

  if [ "$1" = "ragent" ]; then
    setup_ragent_cmd
    setup_ras_cmd

    echo "Запускаем ras с необходимыми параметрами"
    echo "Выполняемая команда: $RAS_CMD"
    $RAS_CMD 2>&1 &  # Запуск ras в фоновом режиме

    echo "Запускаем ragent с необходимыми параметрами"
    echo "Выполняемая команда: $RAGENT_CMD"
    exec $RAGENT_CMD 2>&1
  else
    # Если первый аргумент не 'ragent', выполняем команду, переданную в аргументах
    "$@"
  fi
}

# Вызов главной функции
main "$@"
