/// Where money lands. One source of truth for the whole app — checkout,
/// receipts, and the day close all label channels the same way.
const channelLabels = {
  'cash': 'Cash',
  'opay': 'OPay',
  'palmpay': 'PalmPay',
  'moniepoint': 'Moniepoint',
  'bank': 'Bank transfer',
  'other': 'Other transfer',
  'pos': 'POS',
  'card': 'Card',
  // Fallback for a transfer whose wallet was not recorded.
  'transfer': 'Transfer',
  // Not places money lands, but they appear wherever a payment method is shown.
  'credit': 'Credit',
  'split': 'Split payment',
  'debt_credit': 'Off their balance',
};

/// The wallets a customer transfers into, in the order they appear at checkout.
const transferChannels = ['opay', 'palmpay', 'moniepoint', 'bank'];

String channelLabel(String key) => channelLabels[key] ?? key;
