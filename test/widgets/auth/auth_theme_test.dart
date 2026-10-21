import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openim/pages/login/widgets/login_toolbar.dart';
import 'package:openim/pages/register/set_password/widgets/registration_avatar_picker.dart';
import 'package:openim/pages/register/widgets/register_reference_widgets.dart';
import 'package:openim/widgets/auth/auth_reference.dart';
import 'package:openim_common/openim_common.dart' show AppTokens;

ThemeData _theme(Brightness brightness) => ThemeData(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTokens.accent,
        brightness: brightness,
        surface: AppTokens.surface(dark: brightness == Brightness.dark),
      ),
    );

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
}

void main() {
  for (final dark in [false, true]) {
    final brightness = dark ? Brightness.dark : Brightness.light;
    testWidgets('entry form has readable fields and feedback in $brightness',
        (tester) async {
      final controller = TextEditingController(text: 'account');
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: _theme(brightness),
        home: AuthEntryScaffold(
          greeting: 'Hello,',
          accent: 'Welcome',
          footer: const AuthVersionFooter(version: '3.8.3'),
          child: Column(children: [
            AuthTextField(controller: controller, hint: 'Account'),
            const AuthFieldMessage(text: 'Please check your account'),
            const AuthInfoBanner(
                icon: Icons.shield_outlined, text: 'Verify identity'),
            const AuthFormMessage(text: 'Try again'),
            const AuthPrimaryButton(text: 'Disabled'),
            AuthCodeAction(onSend: () async => false, enabled: false),
          ]),
        ),
      ));
      final field = tester.widget<TextField>(find.byType(TextField));
      final context = tester.element(find.byType(TextField));
      final surface =
          dark ? AppTokens.surfaceDark : AuthReferenceTokens.surface;
      final fill =
          dark ? AppTokens.surfaceAltDark : AuthReferenceTokens.fieldFill;
      expect(Theme.of(context).brightness, brightness);
      expect(_contrast(field.style!.color!, fill), greaterThan(4.5));
      expect(_contrast(field.decoration!.hintStyle!.color!, fill),
          greaterThan(4.5));
      expect(
          _contrast(tester.widget<Text>(find.text('Try again')).style!.color!,
              surface),
          greaterThan(4.5));
      expect(
          _contrast(
              tester.widget<Text>(find.text('Version 3.8.3')).style!.color!,
              surface),
          greaterThan(4.5));
      final disabled = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(disabled.style!.backgroundColor!.resolve({WidgetState.disabled}),
          dark ? AppTokens.surfaceAltDark : AuthReferenceTokens.ink100);
      final bars = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first);
      expect(bars.value.systemNavigationBarColor, surface);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'secondary form adapts custom device verification styles in $brightness',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: _theme(brightness),
        home: AuthFormScaffold(
          title: 'Verify device',
          subtitle: 'Enter the code',
          child: Column(children: [
            const AuthFieldLabel('Code',
                style: AuthReferenceTokens.plainFieldLabel),
            AuthCompoundField(
              controller: controller,
              hint: 'Code',
              inputStyle: AuthReferenceTokens.plainFieldInput,
              hintStyle: AuthReferenceTokens.plainFieldHint,
              leading: AuthCountryCode(code: '+86', onTap: () {}),
            ),
          ]),
        ),
      ));
      expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          dark ? AppTokens.surfaceDark : AuthReferenceTokens.surface);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.style!.fontSize, 18);
      expect(
          field.style!.color,
          dark
              ? _theme(brightness).colorScheme.onSurface
              : AuthReferenceTokens.ink800);
      expect(
          _contrast(
              tester.widget<Text>(find.text('Verify device')).style!.color!,
              dark ? AppTokens.surfaceDark : AuthReferenceTokens.surface),
          greaterThan(4.5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'toolbar contrasts with its actual hero or plain background in $brightness',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: _theme(brightness),
        home: const Scaffold(
            body: Column(children: [
          LoginToolbar(),
          LoginToolbar(onHero: false),
        ])),
      ));
      final actions =
          tester.widgetList<IconButton>(find.byType(IconButton)).toList();
      expect(actions.take(3).map((action) => action.color),
          everyElement(Colors.white));
      expect(actions.skip(3).map((action) => action.color),
          everyElement(_theme(brightness).colorScheme.onSurface));
      expect(tester.takeException(), isNull);
    });

    testWidgets('registration avatar and agreement adapt to $brightness',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: _theme(brightness),
        home: Scaffold(
            body: Column(children: [
          RegistrationAvatarPicker(
              bytes: null, enabled: true, picking: false, onPick: () {}),
          const RegistrationStepHeading(label: 'Profile', step: 2),
          const RegisterPasswordChecklist(password: 'Password1'),
          const RegisterAgreement(),
        ])),
      ));
      expect(
          tester
              .widget<CircleAvatar>(find.byType(CircleAvatar))
              .backgroundColor,
          dark ? AppTokens.surfaceAltDark : AuthReferenceTokens.ink100);
      final caption = tester
          .widget<Text>(find.byKey(const ValueKey('registration-step-2')));
      expect(
          _contrast(caption.style!.color!,
              dark ? AppTokens.surfaceDark : AuthReferenceTokens.surface),
          greaterThan(4.5));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('switching themes retains authentication input and focus',
      (tester) async {
    final controller = TextEditingController(text: 'saved account');
    final focus = FocusNode();
    final mode = ValueNotifier(ThemeMode.light);
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    addTearDown(mode.dispose);
    await tester.pumpWidget(ValueListenableBuilder<ThemeMode>(
      valueListenable: mode,
      builder: (context, current, _) => MaterialApp(
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: current,
        home: AuthEntryScaffold(
          greeting: 'Hello',
          accent: 'Welcome',
          child: AuthTextField(
              controller: controller, focusNode: focus, hint: 'Account'),
        ),
      ),
    ));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    final state = tester.state(find.byType(AuthTextField));
    for (final value in [ThemeMode.dark, ThemeMode.light]) {
      mode.value = value;
      await tester.pumpAndSettle();
      expect(
          identical(tester.state(find.byType(AuthTextField)), state), isTrue);
      expect(controller.text, 'saved account');
      expect(focus.hasFocus, isTrue);
      expect(Theme.of(tester.element(find.byType(TextField))).brightness,
          value == ThemeMode.dark ? Brightness.dark : Brightness.light);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
  });
}
