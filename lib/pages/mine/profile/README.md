# Own profile entry

`MyProfilePage` owns the settings draft and observes the logged-in `IMController`
profile. It reuses `ProfileInfoPage` and `OpenIMProfileService` from Mine; no
message nickname, friend data, or group-member restrictions are used for self.
Opening the page does not wait for a member-profile network lookup. The profile
and Moments use the current SDK user ID, while the displayed ID is the public
account. Draft subscriptions are disposed with the route.

`AppNavigator.startUserProfilePane` routes exact, non-empty self SDK IDs here
before official/peer resolution. Public @account links still resolve to an SDK
ID first. `ChatMessageNavigation` also allows self access before group member
privacy checks. Other members retain those checks.

Reference: `reference-99chat/lib/utils/profile_page_nav.dart`, where
`openUserProfile` sends self targets to `openMyProfileDetail`.
