const activityPages = {
  'home',
  'conversations',
  'contacts',
  'discover',
  'mine',
  'chat',
  'group',
  'contact_profile',
  'search',
  'wallet',
  'wallet_receive',
  'wallet_withdraw',
  'wallet_transfer',
  'wallet_swap',
  'wallet_history',
  'wallet_order',
  'payment',
  'settings',
  'account_security',
  'pay_password',
  'login_devices',
  'moments',
  'live',
  'favorites',
  'other'
};
const connectionActivities = {
  'session_restore',
  'reconnect',
  'connection_lost'
};
const activityActions = {
  'submit_transfer',
  'submit_withdraw',
  'submit_packet',
  'claim_packet',
  'submit_swap',
  'submit_tip',
  'request_sms',
  'change_password',
  'reset_password',
  'change_phone',
  'set_pay_password',
  'reset_pay_password',
  'trust_device',
  'remove_device',
  'friend_apply',
  'message_text',
  'message_image',
  'message_voice',
  'message_video',
  'message_file',
  'message_other',
  'group_join',
  'group_leave',
  'group_create',
  'group_invite',
  'friend_delete'
};
final _safeID = RegExp(r'^[A-Za-z0-9_-]{8,128}$');
bool validActivityID(String? value) => value != null && _safeID.hasMatch(value);

const activityRoutes = <String, String>{
  '/home': 'home',
  '/settings': 'settings',
  '/account_security': 'account_security',
  '/login_devices': 'login_devices',
  '/favorites': 'favorites',
  '/moments': 'moments',
  '/chat': 'chat',
  '/ai_assistant_chat': 'chat',
  '/official_account_chat': 'chat',
  '/chat_setup': 'settings',
  '/group_chat_setup': 'group',
  '/group_profile_panel': 'group',
  '/group_manage': 'group',
  '/group_list': 'group',
  '/create_group': 'group',
  '/group_member_list': 'group',
  '/group_qrcode': 'group',
  '/user_profile_panel': 'contact_profile',
  '/friend_setup': 'contact_profile',
  '/friend_list': 'contacts',
  '/add_contacts_by_search': 'search',
  '/global_search': 'search',
  '/search_group_member': 'search',
  '/account_setup': 'account_security',
  '/my_info': 'mine',
  '/personal_info': 'mine',
  '/wallet_receive': 'wallet_receive',
  '/wallet_withdraw': 'wallet_withdraw',
  '/wallet_transfer': 'wallet_transfer',
  '/wallet_swap': 'wallet_swap',
  '/wallet_history': 'wallet_history',
  '/wallet_order': 'wallet_order',
  '/pay_password': 'pay_password',
  '/wallet': 'wallet',
  '/payment': 'payment',
};
const activityRequestActions = <String, String>{
  '/account/code/send': 'request_sms',
  '/account/password/change': 'change_password',
  '/account/password/reset': 'reset_password',
  '/account/phone/bind': 'change_phone',
  '/account/phone/change': 'change_phone',
  '/account/device/remove': 'remove_device',
  '/account/device/remove_others': 'remove_device',
  '/account/device/trust': 'trust_device',
  '/chat/fund/pay-password/code': 'request_sms',
  '/chat/fund/withdrawal-security/code': 'request_sms',
  '/chat/fund/pay-password': 'set_pay_password',
  '/chat/fund/pay-password/reset': 'reset_pay_password',
  '/chat/fund/transfers': 'submit_transfer',
  '/chat/fund/packets': 'submit_packet',
  '/chat/fund/swaps': 'submit_swap',
  '/chat/fund/withdrawals': 'submit_withdraw',
  '/chat/friend-apply': 'friend_apply',
};
String? activityRequestAction(String path) {
  if (RegExp(r'^/chat/fund/packets/[^/]+/claim$').hasMatch(path)) {
    return 'claim_packet';
  }
  if (RegExp(r'^/group-live/api/v1/live/[^/]+/tip$').hasMatch(path)) {
    return 'submit_tip';
  }
  return activityRequestActions[path];
}
