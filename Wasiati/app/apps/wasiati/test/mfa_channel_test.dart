import 'package:flutter_test/flutter_test.dart';
import 'package:wasiati/features/auth/domain/auth_models.dart';

/// `via` decides what the MFA screen TELLS the user, and getting it wrong is worse than
/// showing nothing: an authenticator user who is told "we texted you" waits for a message
/// that will never arrive, next to a Resend button that cannot help them.
///
/// This was a real defect. `parse` mapped every unrecognised value to [OtpChannel.sms],
/// so when the backend began answering `via: 'totp'` for enrolled accounts, the client
/// silently read it as SMS — the failure looked like a broken text-message pipeline
/// rather than a client that had never heard of authenticator apps.
void main() {
  group('OtpChannel.parse', () {
    test('recognises an authenticator app rather than mistaking it for SMS', () {
      expect(OtpChannel.parse('totp'), OtpChannel.totp);
    });

    test('still reads the message channels', () {
      expect(OtpChannel.parse('sms'), OtpChannel.sms);
      expect(OtpChannel.parse('email'), OtpChannel.email);
    });

    test('recognises WhatsApp, which is a different app to check than Messages', () {
      // Saudi codes are routed over WhatsApp for cost. Reading it as SMS would send the
      // user to the wrong app and look exactly like a code that never arrived.
      expect(OtpChannel.parse('whatsapp'), OtpChannel.whatsapp);
    });

    test('falls back to SMS for anything unknown, so an older backend still logs in', () {
      // Deliberate: the fallback exists so a client newer than its server does not break
      // the login flow outright. It is only wrong when a value we DO support is missing
      // from the switch — which is exactly what happened with totp.
      expect(OtpChannel.parse(null), OtpChannel.sms);
      expect(OtpChannel.parse('carrier-pigeon'), OtpChannel.sms);
      expect(OtpChannel.parse(42), OtpChannel.sms);
    });
  });

  group('isSelfServed', () {
    test('only the authenticator needs nothing sent to it', () {
      // Drives whether the resend control renders at all: there is nothing to re-send
      // when the code is generated on the user's own device.
      expect(OtpChannel.totp.isSelfServed, isTrue);
      expect(OtpChannel.sms.isSelfServed, isFalse);
      expect(OtpChannel.email.isSelfServed, isFalse);
      // WhatsApp IS sent, so resend applies to it exactly as it does to a text.
      expect(OtpChannel.whatsapp.isSelfServed, isFalse);
    });
  });
}
