// Этот файл: lib/src/services/deepseek/rules.dart.
// Простыми словами: это часть backend. Он принимает запросы от приложения, работает с базой, оплатой и внешними сервисами.
// Комментарии в файле объясняют, что делает код и что он возвращает, без сложных слов.

// Это базовое правило поведения AI на случай,
// если в запросе нет более точной настройки.
//
// Для продукта это страховка:
// даже если пользователь не выбрал конкретного психолога,
// AI всё равно отвечает в общей полезной роли, а не "как придётся".
const String defaultDeepSeekSystemPrompt = 'You are a helpful assistant.';

/// Функция deepSeekLanguageInstructionForCode: выполняет шаг deepSeekLanguageInstructionForCode в этой части программы. Возвращает текст или пустое значение, если текста нет.
/// Возвращает текст или пустое значение, если текста нет.
String? deepSeekLanguageInstructionForCode(String? rawLanguageCode) {
  // Здесь определяется язык, на котором AI должен отвечать клиенту.
  //
  // Код языка заранее приводится к единому виду,
  // чтобы проект одинаково понимал разные варианты записи.
  final normalizedCode = rawLanguageCode?.trim().toLowerCase();

  switch (normalizedCode) {
    // Язык задаётся отдельным правилом.
    //
    // Это удобно для бизнеса:
    // один и тот же психолог может работать на нескольких языках,
    // а смена языка не требует переписывать сам сценарий его поведения.
    case 'ru':
      return 'Reply in Russian only. Ignore any earlier language from the conversation or character prompt if it conflicts with Russian. Keep the answer natural, fluent and helpful.';
    case 'en':
      return 'Reply in English only. Ignore any earlier language from the conversation or character prompt if it conflicts with English. Keep the answer natural, fluent and helpful.';
    case 'be':
      return 'Reply in Belarusian only. Ignore any earlier language from the conversation or character prompt if it conflicts with Belarusian. Keep the answer natural, fluent and helpful.';
    default:
      // Если язык не распознан, отдельное правило не добавляется.
      // Тогда AI ориентируется на остальной контекст диалога.
      return null;
  }
}
