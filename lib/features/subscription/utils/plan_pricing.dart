/// 套餐折算计算（纯函数，无副作用，可单测）。
///
/// 付费墙年付卡片需要展示「立省 X%」与「≈ 每月价」两个转化提示。
/// 这些都不能硬编码——价格字符串（含币种符号）只能来自平台 SDK，且各地区
/// 币种符号位置、千分位/小数分隔符各异。本文件负责从本地化价格串里**容错地**
/// 解析金额，并据月付/年付价格折算。任何一步解析失败都返回空结果，UI 不展示折算，
/// 绝不显示一个算错的数字。
library;

import '../models/subscription_plan.dart';

/// 年付折算结果。
///
/// [perMonth] 为带币种符号的每月折合价字符串（如 `US$3.33`）；
/// [savePercent] 为相对「月付×12」的节省百分比（取整）。
/// 任一为 null 表示无法可靠计算，UI 应隐藏对应提示。
typedef YearlyValue = ({String? perMonth, int? savePercent});

/// 无折算结果（解析失败 / 数据不足时返回）。
const YearlyValue _empty = (perMonth: null, savePercent: null);

/// 根据月付与年付套餐计算年付的「每月折合价」与「节省百分比」。
///
/// 折扣按用户首年实际支付价计算：年付有付费 intro offer 时使用优惠价，
/// 否则使用普通年付价。仅当价格都能解析为正数、且年付首年价确实比
/// 「月付×12」便宜时才返回有效值，否则返回 [_empty]。
YearlyValue computeYearlyValue(
  SubscriptionPlan monthly,
  SubscriptionPlan yearly,
) {
  final monthlyAmount = parseLocalizedPriceAmount(monthly.priceString);
  final effectiveYearlyPrice =
      yearly.introOffer != null && !yearly.introOffer!.isFreeTrial
      ? yearly.introOffer!.priceString
      : yearly.priceString;
  final yearlyAmount = parseLocalizedPriceAmount(effectiveYearlyPrice);
  if (monthlyAmount == null || yearlyAmount == null) return _empty;
  if (monthlyAmount <= 0 || yearlyAmount <= 0) return _empty;

  final fullPrice = monthlyAmount * 12;
  if (fullPrice <= yearlyAmount) return _empty; // 年付不便宜，不展示折算

  final savePercent = ((1 - yearlyAmount / fullPrice) * 100).round();
  final perMonthAmount = yearlyAmount / 12;
  final perMonth = formatLocalizedPriceLike(
    effectiveYearlyPrice,
    perMonthAmount,
  );
  return (perMonth: perMonth, savePercent: savePercent);
}

/// 计算平台付费 intro offer 相对续费价的折扣百分比。
///
/// 仅处理非免费试用的 intro offer；免费试用由 CTA 和套餐卡副标题披露，避免在
/// 顶部促销条重复展示。价格解析失败、优惠价不低于续费价时返回 null。
int? computeIntroOfferDiscountPercent(SubscriptionPlan plan) {
  if (isIntroOfferDiscounted(plan) != true) return null;

  final offer = plan.introOffer;
  if (offer == null) return null;
  final introAmount = parseLocalizedPriceAmount(offer.priceString);
  final renewalAmount = parseLocalizedPriceAmount(offer.renewalPriceString);
  if (introAmount == null || renewalAmount == null) return null;
  return ((1 - introAmount / renewalAmount) * 100).round();
}

/// 判断付费 intro offer 价格是否低于续费价。
///
/// 返回 true 表示可确认有折扣；false 表示可确认没有价格优势；null 表示无付费
/// intro offer 或价格字符串无法可靠解析，调用方可选择隐藏或回退为具体条款文案。
bool? isIntroOfferDiscounted(SubscriptionPlan plan) {
  final offer = plan.introOffer;
  if (offer == null || offer.isFreeTrial) return null;

  final introAmount = parseLocalizedPriceAmount(offer.priceString);
  final renewalAmount = parseLocalizedPriceAmount(offer.renewalPriceString);
  if (introAmount == null || renewalAmount == null) return null;
  if (introAmount <= 0 || renewalAmount <= 0) return null;
  return introAmount < renewalAmount;
}

/// 按续费价格串和百分比折扣推导 intro offer 价格串。
///
/// Paddle 新 plans DTO 只返回地区化续费价与折扣百分比；真实扣款仍由 Paddle
/// checkout 决定，这里只把同一价格模板转换成 UI 展示用的优惠价。
String? discountedPriceString(String renewalPriceString, num discountPercent) {
  if (!(discountPercent > 0 && discountPercent <= 100)) return null;
  final renewalAmount = parseLocalizedPriceAmount(renewalPriceString);
  if (renewalAmount == null || renewalAmount < 0) return null;
  final discountedAmount = renewalAmount * (100 - discountPercent) / 100;
  return formatLocalizedPriceLike(renewalPriceString, discountedAmount);
}

/// 从本地化价格串中提取数值金额，无法解析返回 null。
///
/// 处理思路：先取出所有数字与分隔符（`. ,`），再根据「最后一个分隔符」判定它是
/// 小数点还是千分位——最后一个分隔符后跟 1~2 位数字视为小数点，其余分隔符按千分位丢弃。
double? parseLocalizedPriceAmount(String priceString) {
  final match = RegExp(r'[0-9][0-9.,]*').firstMatch(priceString);
  if (match == null) return null;
  final raw = match.group(0)!;

  final lastSep = raw.lastIndexOf(RegExp(r'[.,]'));
  if (lastSep == -1) return double.tryParse(raw);

  final decimals = raw.length - lastSep - 1;
  final intPart = raw.substring(0, lastSep).replaceAll(RegExp(r'[.,]'), '');
  final fracPart = raw.substring(lastSep + 1);
  // 最后一段超过 2 位，更可能是千分位（如 1,000）而非小数。
  if (decimals > 2) {
    return double.tryParse('$intPart$fracPart');
  }
  return double.tryParse('$intPart.$fracPart');
}

/// 按 [template] 的币种符号与位置，把 [amount] 格式化为同形态的价格串。
///
/// 例：template=`US$39.99`, amount=3.3325 → `US$3.33`；
/// template=`39,99 €`, amount=3.33 → `3.33 €`（保留符号在原侧）。
String formatLocalizedPriceLike(String template, double amount) {
  final numberMatch = RegExp(r'[0-9][0-9.,]*').firstMatch(template);
  final value = amount.toStringAsFixed(2);
  if (numberMatch == null) return value;
  final prefix = template.substring(0, numberMatch.start).trim();
  final suffix = template.substring(numberMatch.end).trim();
  // 还原符号与数字的排版：前缀符号紧贴数字，后缀符号空一格（贴合常见币种写法）。
  return [
    if (prefix.isNotEmpty) prefix,
    value,
    if (suffix.isNotEmpty) ' $suffix',
  ].join();
}
