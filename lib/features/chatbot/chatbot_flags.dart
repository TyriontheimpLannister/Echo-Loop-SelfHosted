/// 通用 Chatbot 组件的编译期开关。
///
/// 编译期开关保留硬停能力；运行期全球显隐由 remote config
/// （RemoteFeature.aiChatAssistant）控制。
library;

/// 是否对用户暴露 chatbot 入口（句子讲解页 / 学习任务页 AppBar AI 按钮等）。
///
/// 当前 **true**：后端流式端点已上线（2026-07-21 起走真实后端）。
/// 如需全平台紧急下线改回 false；仅运行期隐藏用 remote config。
const bool kChatbotEnabled = true;

/// 是否使用 debug 假流实现（[FakeChatApiClient]）替代真实网络客户端。
///
/// 默认 **false**（走真实后端）。仅本地联调 / 手动验收（后端未就绪时跑通流式/停止/
/// markdown/多轮）时临时置 true；不进 release 逻辑分支。
const bool kChatbotUseFakeApi = false;
