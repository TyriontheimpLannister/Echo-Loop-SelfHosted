/// 句子级 AI 助手入口按钮（AppBar action）。
///
/// 句子详情页与各学习任务页（逐句精听/难句跟读/难句复习/收藏复习）共用的
/// 单一入口来源：显隐开关、图标、ChatbotConfig 组装都集中在此，避免多处复制。
library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../l10n/app_localizations.dart';
import '../chatbot_flags.dart';
import '../chatbot_sheet.dart';
import '../models/chatbot_config.dart';

/// AI 聊天入口显示规则：仅保留编译期开关的硬停能力。
///
/// 自托管版已不再轮询官方 remote config；继续依赖旧缓存可能让已部署的
/// 局域网聊天入口被永久隐藏。因此句子级辅导入口不接受远程配置控制。
bool shouldShowAiChatAssistantEntry({required bool chatbotEnabled}) =>
    chatbotEnabled;

/// 构造句子级聊天配置；AppBar 与文本选区入口必须复用同一会话身份。
ChatbotConfig sentenceChatbotConfig(BuildContext context, String sentenceText) {
  final l10n = AppLocalizations.of(context)!;
  return ChatbotConfig(
    // 用完整句子做内存会话 key，避免 hash 碰撞，也让同句跨页面复用会话。
    sessionId: 'sentence:$sentenceText',
    endpoint: '/api/v1/stream/chat/sentence',
    context: {'sentence': sentenceText},
    title: l10n.chatSentenceTitle,
    inputPlaceholder: l10n.chatInputPlaceholder,
    contextSummary: sentenceText,
  );
}

/// 打开句子级 AI Sheet；[initialQuote] 只进入引用待发送区，不自动提问。
Future<void> showSentenceChatbotSheet({
  required BuildContext context,
  required String sentenceText,
  String? initialQuote,
}) {
  return showChatbotSheet(
    context: context,
    config: sentenceChatbotConfig(context, sentenceText),
    initialQuote: initialQuote,
  );
}

/// 句子 AI 助手入口按钮。
///
/// 开关关闭或 [sentenceText] 为空（句子未就绪）时自隐藏（渲染空 widget），
/// 调用方无需判空。点击时先执行 [onBeforeOpen]（任务页用来暂停自动推进，
/// 语义同各页设置按钮），再以 bottom sheet 打开 chatbot。
class SentenceChatButton extends StatelessWidget {
  /// 当前句子文本；会话按句子内容归属（相同句子跨页面复用同一会话）。
  final String sentenceText;

  /// 打开面板前回调（可选）：任务页在此暂停自动推进/等待用户。
  final VoidCallback? onBeforeOpen;

  const SentenceChatButton({
    super.key,
    required this.sentenceText,
    this.onBeforeOpen,
  });

  @override
  Widget build(BuildContext context) {
    final show = shouldShowAiChatAssistantEntry(
      chatbotEnabled: kChatbotEnabled,
    );
    if (!show || sentenceText.isEmpty) return const SizedBox.shrink();

    // 右侧留白：让 action 按钮不贴相邻控件/屏幕右缘，与左侧图标边距对称。
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: IconButton(
        // 渐变多色图标，保留原始配色不做 colorFilter 染色。
        icon: SvgPicture.asset(
          'assets/icon/chat/use-ai-chat.svg',
          width: 24,
          height: 24,
        ),
        tooltip: AppLocalizations.of(context)!.chatOpenTooltip,
        onPressed: () {
          onBeforeOpen?.call();
          showSentenceChatbotSheet(
            context: context,
            sentenceText: sentenceText,
          );
        },
      ),
    );
  }
}

/// 解析结果下方的显式追问入口。
///
/// 与 AppBar 图标复用同一个句子会话，但使用带文字的按钮，避免用户看完解析后
/// 还需要猜测右上角图标的用途。
class SentenceChatFollowUpButton extends StatelessWidget {
  /// 当前解析对应的完整句子。
  final String sentenceText;

  /// 打开聊天前暂停学习任务自动推进。
  final VoidCallback? onBeforeOpen;

  const SentenceChatFollowUpButton({
    super.key,
    required this.sentenceText,
    this.onBeforeOpen,
  });

  @override
  Widget build(BuildContext context) {
    final show = shouldShowAiChatAssistantEntry(
      chatbotEnabled: kChatbotEnabled,
    );
    if (!show || sentenceText.isEmpty) return const SizedBox.shrink();

    return FilledButton.tonalIcon(
      key: const ValueKey('sentence-chat-follow-up'),
      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
      label: Text(AppLocalizations.of(context)!.chatOpenTooltip),
      onPressed: () {
        onBeforeOpen?.call();
        showSentenceChatbotSheet(context: context, sentenceText: sentenceText);
      },
    );
  }
}
