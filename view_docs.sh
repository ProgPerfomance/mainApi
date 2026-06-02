#!/bin/bash

# Kirill API - Documentation Viewer
# Автоматически открывает API документацию

echo "╔════════════════════════════════════════════════════════════╗"
echo "║           Открытие API документации                       ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Check if openapi.yaml exists
if [ ! -f "openapi.yaml" ]; then
    echo "❌ Файл openapi.yaml не найден!"
    exit 1
fi

echo "📖 Документация: openapi.yaml"
echo ""
echo "Выберите способ просмотра:"
echo ""
echo "1) Swagger Editor (онлайн) - РЕКОМЕНДУЕТСЯ"
echo "2) Swagger UI (Docker)"
echo "3) Просто показать путь к файлу"
echo "4) Открыть файл в редакторе"
echo ""
read -p "Выберите (1-4): " choice

case $choice in
    1)
        echo ""
        echo "🌐 Открываем Swagger Editor..."
        echo ""
        echo "Инструкция:"
        echo "1. Откроется Swagger Editor в браузере"
        echo "2. Нажмите: File → Import file"
        echo "3. Выберите файл: $(pwd)/openapi.yaml"
        echo ""
        echo "Или скопируйте содержимое файла и вставьте в редактор"
        echo ""
        read -p "Нажмите Enter чтобы открыть Swagger Editor..."

        # Open Swagger Editor
        if [[ "$OSTYPE" == "darwin"* ]]; then
            open "https://editor.swagger.io/"
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            xdg-open "https://editor.swagger.io/"
        else
            echo "Откройте вручную: https://editor.swagger.io/"
        fi

        echo ""
        echo "📄 Путь к файлу для импорта:"
        echo "$(pwd)/openapi.yaml"
        ;;

    2)
        echo ""
        echo "🐳 Запускаем Swagger UI через Docker..."

        # Check if Docker is running
        if ! docker info > /dev/null 2>&1; then
            echo "❌ Docker не запущен. Пожалуйста, запустите Docker и попробуйте снова."
            exit 1
        fi

        # Run Swagger UI
        echo "Запуск контейнера..."
        docker run -d -p 8081:8080 \
            -e SWAGGER_JSON=/openapi.yaml \
            -v "$(pwd)/openapi.yaml:/openapi.yaml" \
            --name kirill_api_docs \
            swaggerapi/swagger-ui

        if [ $? -eq 0 ]; then
            echo "✅ Swagger UI запущен!"
            echo ""
            echo "📖 Документация доступна по адресу:"
            echo "   http://localhost:8081"
            echo ""
            sleep 2

            # Open in browser
            if [[ "$OSTYPE" == "darwin"* ]]; then
                open "http://localhost:8081"
            elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
                xdg-open "http://localhost:8081"
            fi

            echo ""
            echo "Для остановки выполните:"
            echo "   docker stop kirill_api_docs && docker rm kirill_api_docs"
        else
            echo "❌ Ошибка при запуске Docker контейнера"
            echo ""
            echo "Возможно контейнер уже запущен. Попробуйте:"
            echo "   docker stop kirill_api_docs && docker rm kirill_api_docs"
            echo "Затем запустите скрипт снова"
        fi
        ;;

    3)
        echo ""
        echo "📄 Путь к файлу документации:"
        echo "$(pwd)/openapi.yaml"
        echo ""
        echo "Скопировано в буфер обмена (если возможно)"

        # Try to copy to clipboard
        if command -v pbcopy &> /dev/null; then
            echo "$(pwd)/openapi.yaml" | pbcopy
            echo "✅ Путь скопирован в буфер обмена"
        elif command -v xclip &> /dev/null; then
            echo "$(pwd)/openapi.yaml" | xclip -selection clipboard
            echo "✅ Путь скопирован в буфер обмена"
        fi
        ;;

    4)
        echo ""
        echo "📝 Открываем в редакторе..."

        # Try to open with default editor
        if command -v code &> /dev/null; then
            code openapi.yaml
            echo "✅ Открыто в VS Code"
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            open -a TextEdit openapi.yaml
            echo "✅ Открыто в TextEdit"
        elif command -v nano &> /dev/null; then
            nano openapi.yaml
        else
            echo "$(pwd)/openapi.yaml"
        fi
        ;;

    *)
        echo "❌ Неверный выбор"
        exit 1
        ;;
esac

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  Документация содержит:                                   ║"
echo "║  - Все API endpoints                                      ║"
echo "║  - Примеры запросов/ответов                               ║"
echo "║  - Схемы данных                                           ║"
echo "║  - Коды ошибок                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"

