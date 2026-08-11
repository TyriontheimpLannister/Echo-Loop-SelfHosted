/// SentenceChatButton 测试：开关显隐规则 + 组件渲染 + onBeforeOpen 回调。
library;

import 'package:echo_loop/features/chatbot/widgets/sentence_chat_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chatbot_widget_harness.dart';

void main() {
  group('shouldShowAiChatAssistantEntry', () {
    test('编译期开关开启时显示入口', () {
      expect(shouldShowAiChatAssistantEntry(chatbotEnabled: true), isTrue);
    });

    test('编译期开关关闭时隐藏入口', () {
      expect(shouldShowAiChatAssistantEntry(chatbotEnabled: false), isFalse);
    });
  });

  group('SentenceChatButton', () {
    testWidgets('自托管模式不读取远程配置，句子非空时渲染按钮', (tester) async {
      await pumpChatWidget(
        tester,
        const SentenceChatButton(sentenceText: 'Hello world.'),
      );
      expect(find.byType(IconButton), findsOneWidget);
    });

    testWidgets('句子为空（未就绪）时不渲染按钮', (tester) async {
      await pumpChatWidget(tester, const SentenceChatButton(sentenceText: ''));
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('点击时先触发 onBeforeOpen（任务页借此暂停自动推进）', (tester) async {
      var beforeOpenCalled = false;
      await pumpChatWidget(
        tester,
        SentenceChatButton(
          sentenceText: 'Hello world.',
          onBeforeOpen: () => beforeOpenCalled = true,
        ),
      );
      // 只验证回调时序，不 pump sheet 内容（ChatView 依赖网络/订阅一整套 provider）。
      await tester.tap(find.byType(IconButton));
      expect(beforeOpenCalled, isTrue);
    });
  });

  group('SentenceChatFollowUpButton', () {
    testWidgets('解析结果入口使用明确的 Ask AI 文字', (tester) async {
      await pumpChatWidget(
        tester,
        const SentenceChatFollowUpButton(sentenceText: 'Hello world.'),
      );

      expect(
        find.byKey(const ValueKey('sentence-chat-follow-up')),
        findsOneWidget,
      );
      expect(find.text('Ask AI'), findsOneWidget);
    });

    testWidgets('句子为空时不显示追问入口', (tester) async {
      await pumpChatWidget(
        tester,
        const SentenceChatFollowUpButton(sentenceText: ''),
      );

      expect(
        find.byKey(const ValueKey('sentence-chat-follow-up')),
        findsNothing,
      );
    });
  });
}
